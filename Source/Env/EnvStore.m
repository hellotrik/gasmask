/***************************************************************************
 * EnvStore implementation
 ***************************************************************************/

#import "EnvStore.h"

static NSString *const EnvMaskStoreDirName = @"Env Mask";

@interface EnvTarget ()
{
	NSString *_targetId;
	NSString *_name;
	NSString *_executablePath;
	NSArray<NSString *> *_layerIds;
}
@end

@implementation EnvTarget

+ (EnvTarget *)targetWithId:(NSString *)targetId
					   name:(NSString *)name
			 executablePath:(NSString *)executablePath
				   layerIds:(NSArray<NSString *> *)layerIds
{
	EnvTarget *t = [EnvTarget new];
	t->_targetId = [targetId copy];
	t->_name = [name copy];
	t->_executablePath = [executablePath copy];
	t->_layerIds = [layerIds copy] ?: @[];
	return t;
}

- (NSString *)targetId { return _targetId; }
- (NSString *)name { return _name; }
- (NSString *)executablePath { return _executablePath; }
- (NSArray<NSString *> *)layerIds { return _layerIds; }

+ (EnvTarget *)targetFromJsonObject:(NSDictionary *)obj error:(NSError **)error
{
	if (![obj isKindOfClass:[NSDictionary class]]) {
		if (error) *error = [NSError errorWithDomain:@"EnvMask" code:20 userInfo:@{NSLocalizedDescriptionKey: @"Target JSON is not a dictionary"}];
		return nil;
	}
	NSString *tid = obj[@"id"];
	NSString *name = obj[@"name"] ?: tid;
	NSString *execPath = obj[@"executablePath"];
	NSArray *layerIds = obj[@"layerIds"] ?: @[];

	if (![tid isKindOfClass:[NSString class]] || [tid length] == 0) {
		if (error) *error = [NSError errorWithDomain:@"EnvMask" code:21 userInfo:@{NSLocalizedDescriptionKey: @"Target id missing"}];
		return nil;
	}
	if (![execPath isKindOfClass:[NSString class]] || [execPath length] == 0) {
		if (error) *error = [NSError errorWithDomain:@"EnvMask" code:22 userInfo:@{NSLocalizedDescriptionKey: @"Target executablePath missing"}];
		return nil;
	}
	if (![layerIds isKindOfClass:[NSArray class]]) {
		layerIds = @[];
	}

	NSMutableArray *filtered = [NSMutableArray array];
	for (id item in (NSArray *)layerIds) {
		if ([item isKindOfClass:[NSString class]] && [item length] > 0) {
			[filtered addObject:item];
		}
	}

	return [EnvTarget targetWithId:tid name:name executablePath:execPath layerIds:filtered];
}

+ (NSDictionary *)toJsonObjectFromTarget:(EnvTarget *)target
{
	return @{
		@"id": target.targetId ?: @"",
		@"name": target.name ?: target.targetId ?: @"",
		@"executablePath": target.executablePath ?: @"",
		@"layerIds": target.layerIds ?: @[]
	};
}

@end

@implementation EnvStore

static EnvStore *sharedInstance = nil;

+ (EnvStore *)defaultInstance
{
	if (!sharedInstance) {
		sharedInstance = [EnvStore new];
	}
	return sharedInstance;
}

- (NSString *)rootDirectory
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
	NSString *lib = [paths firstObject] ?: NSHomeDirectory();
	return [lib stringByAppendingPathComponent:EnvMaskStoreDirName];
}

- (NSString *)layersFilePath
{
	return [[self rootDirectory] stringByAppendingPathComponent:@"layers.json"];
}

- (NSString *)targetsFilePath
{
	return [[self rootDirectory] stringByAppendingPathComponent:@"targets.json"];
}

- (BOOL)ensureRootDirectoryExists:(NSError **)error
{
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *dir = [self rootDirectory];
	BOOL isDir = NO;
	if ([fm fileExistsAtPath:dir isDirectory:&isDir]) {
		return isDir;
	}
	return [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:error];
}

- (NSData *)readJsonDataAtPath:(NSString *)path
{
	return [NSData dataWithContentsOfFile:path options:0 error:NULL];
}

- (BOOL)writeJsonData:(NSData *)data toPath:(NSString *)path error:(NSError **)error
{
	// NSDataWritingAtomic already writes to a temp file and renames, which is
	// sufficient and less error-prone than manual tmp management.
	return [data writeToFile:path options:NSDataWritingAtomic error:error];
}

- (NSArray<EnvLayer *> *)defaultLayers
{
	EnvLayer *base = [EnvLayer layerWithId:@"base"
									  name:@"base"
								   enabled:YES
								  priority:10
									   ops:@[]];
	// Temp layer: user’s quick ad-hoc variables. Disabled by default.
	EnvLayer *temp = [EnvLayer layerWithId:@"temp"
									  name:@"Temp"
								   enabled:NO
								  priority:90
									   ops:@[]];
	return @[base, temp];
}

- (NSArray<EnvLayer *> *)ensureTempLayerExists
{
	NSArray<EnvLayer *> *layers = [self loadLayers];
	for (EnvLayer *l in layers) {
		if ([l.layerId isEqualToString:@"temp"]) {
			return layers;
		}
	}
	NSMutableArray *updated = [layers mutableCopy];
	EnvLayer *temp = [EnvLayer layerWithId:@"temp" name:@"Temp" enabled:NO priority:90 ops:@[]];
	[updated addObject:temp];
	[self saveLayers:updated error:NULL];
	return updated;
}

- (NSArray<EnvLayer *> *)upsertTempOpWithType:(EnvVarOpType)type key:(NSString *)key value:(NSString *)value
{
	if ([key length] == 0) return [self ensureTempLayerExists];
	NSString *trimKey = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([trimKey length] == 0) return [self ensureTempLayerExists];

	NSArray<EnvLayer *> *layers = [self ensureTempLayerExists];
	NSMutableArray<EnvLayer *> *updatedLayers = [NSMutableArray arrayWithCapacity:[layers count]];

	for (EnvLayer *l in layers) {
		if (![l.layerId isEqualToString:@"temp"]) {
			[updatedLayers addObject:l];
			continue;
		}

		NSMutableArray<EnvVarOp *> *ops = [NSMutableArray array];
		for (EnvVarOp *op in l.ops) {
			if (![op.key isEqualToString:trimKey]) {
				[ops addObject:op];
			}
		}

		EnvVarOp *newOp = nil;
		switch (type) {
			case EnvVarOpTypeSet:
				newOp = [EnvVarOp setOpWithKey:trimKey value:(value ?: @"")];
				break;
			case EnvVarOpTypeAppendPath:
				newOp = [EnvVarOp appendPathOpWithKey:trimKey value:(value ?: @"")];
				break;
			case EnvVarOpTypeRemove:
				newOp = [EnvVarOp removeOpWithKey:trimKey];
				break;
		}
		if (newOp) [ops addObject:newOp];

		// Any explicit temp op implies temp is enabled (convenience).
		EnvLayer *nl = [EnvLayer layerWithId:l.layerId name:l.name enabled:YES priority:l.priority ops:ops];
		[updatedLayers addObject:nl];
	}

	[self saveLayers:updatedLayers error:NULL];
	return updatedLayers;
}

- (NSArray<EnvLayer *> *)clearTempLayerOps
{
	NSArray<EnvLayer *> *layers = [self ensureTempLayerExists];
	NSMutableArray<EnvLayer *> *updatedLayers = [NSMutableArray arrayWithCapacity:[layers count]];
	for (EnvLayer *l in layers) {
		if ([l.layerId isEqualToString:@"temp"]) {
			EnvLayer *nl = [EnvLayer layerWithId:l.layerId name:l.name enabled:NO priority:l.priority ops:@[]];
			[updatedLayers addObject:nl];
		} else {
			[updatedLayers addObject:l];
		}
	}
	[self saveLayers:updatedLayers error:NULL];
	return updatedLayers;
}

- (NSArray<EnvLayer *> *)loadLayers
{
	[self ensureRootDirectoryExists:NULL];
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *path = [self layersFilePath];

	if (![fm fileExistsAtPath:path]) {
		[self saveLayers:[self defaultLayers] error:NULL];
	}

	NSData *data = [self readJsonDataAtPath:path];
	if (!data) {
		return [self defaultLayers];
	}

	id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
	if (![json isKindOfClass:[NSArray class]]) {
		return [self defaultLayers];
	}

	NSMutableArray<EnvLayer *> *layers = [NSMutableArray array];
	for (id item in (NSArray *)json) {
		NSError *err = nil;
		EnvLayer *layer = [EnvLayer layerFromJsonObject:item error:&err];
		if (layer) [layers addObject:layer];
	}

	if ([layers count] == 0) {
		return [self defaultLayers];
	}
	return layers;
}

- (BOOL)saveLayers:(NSArray<EnvLayer *> *)layers error:(NSError **)error
{
	if (![self ensureRootDirectoryExists:error]) {
		return NO;
	}

	NSMutableArray *arr = [NSMutableArray arrayWithCapacity:[layers count]];
	for (EnvLayer *l in layers) {
		[arr addObject:[EnvLayer toJsonObjectFromLayer:l]];
	}

	NSData *data = [NSJSONSerialization dataWithJSONObject:arr options:NSJSONWritingPrettyPrinted error:error];
	if (!data) {
		return NO;
	}
	return [self writeJsonData:data toPath:[self layersFilePath] error:error];
}

- (NSArray<EnvTarget *> *)loadTargets
{
	[self ensureRootDirectoryExists:NULL];
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *path = [self targetsFilePath];
	if (![fm fileExistsAtPath:path]) {
		// Provide one safe default target for smoke testing / onboarding.
		EnvTarget *textEdit = [EnvTarget targetWithId:@"textedit"
												 name:@"TextEdit"
									  executablePath:@"/System/Applications/TextEdit.app/Contents/MacOS/TextEdit"
											layerIds:@[]];
		[self saveTargets:@[textEdit] error:NULL];
	}

	NSData *data = [self readJsonDataAtPath:path];
	if (!data) return @[];

	id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
	if (![json isKindOfClass:[NSArray class]]) return @[];

	NSMutableArray<EnvTarget *> *targets = [NSMutableArray array];
	for (id item in (NSArray *)json) {
		NSError *err = nil;
		EnvTarget *t = [EnvTarget targetFromJsonObject:item error:&err];
		if (t) [targets addObject:t];
	}
	return targets;
}

- (BOOL)saveTargets:(NSArray<EnvTarget *> *)targets error:(NSError **)error
{
	if (![self ensureRootDirectoryExists:error]) {
		return NO;
	}

	NSMutableArray *arr = [NSMutableArray arrayWithCapacity:[targets count]];
	for (EnvTarget *t in targets) {
		[arr addObject:[EnvTarget toJsonObjectFromTarget:t]];
	}

	NSData *data = [NSJSONSerialization dataWithJSONObject:arr options:NSJSONWritingPrettyPrinted error:error];
	if (!data) return NO;
	return [self writeJsonData:data toPath:[self targetsFilePath] error:error];
}

- (NSArray<EnvLayer *> *)toggleLayerEnabledById:(NSString *)layerId
{
	NSArray<EnvLayer *> *layers = [self loadLayers];
	NSMutableArray<EnvLayer *> *updated = [NSMutableArray arrayWithCapacity:[layers count]];

	for (EnvLayer *l in layers) {
		if ([l.layerId isEqualToString:layerId]) {
			EnvLayer *nl = [EnvLayer layerWithId:l.layerId
											name:l.name
										 enabled:!l.enabled
										priority:l.priority
											 ops:l.ops];
			[updated addObject:nl];
		} else {
			[updated addObject:l];
		}
	}

	[self saveLayers:updated error:NULL];
	return updated;
}

@end

