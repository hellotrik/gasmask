/***************************************************************************
 * EnvLayer / EnvVarOp implementation
 ***************************************************************************/

#import "EnvLayer.h"

@interface EnvVarOp ()
{
	EnvVarOpType _type;
	NSString *_key;
	NSString *_value;
}
@end

@implementation EnvVarOp

+ (EnvVarOp *)setOpWithKey:(NSString *)key value:(NSString *)value
{
	EnvVarOp *op = [EnvVarOp new];
	op->_type = EnvVarOpTypeSet;
	op->_key = [key copy];
	op->_value = [value copy] ?: @"";
	return op;
}

+ (EnvVarOp *)appendPathOpWithKey:(NSString *)key value:(NSString *)value
{
	EnvVarOp *op = [EnvVarOp new];
	op->_type = EnvVarOpTypeAppendPath;
	op->_key = [key copy];
	op->_value = [value copy] ?: @"";
	return op;
}

+ (EnvVarOp *)removeOpWithKey:(NSString *)key
{
	EnvVarOp *op = [EnvVarOp new];
	op->_type = EnvVarOpTypeRemove;
	op->_key = [key copy];
	return op;
}

- (EnvVarOpType)type { return _type; }
- (NSString *)key { return _key; }
- (NSString *)value { return _value; }

@end

@interface EnvLayer ()
{
	NSString *_layerId;
	NSString *_name;
	BOOL _enabled;
	NSInteger _priority;
	NSArray<EnvVarOp *> *_ops;
}
@end

@implementation EnvLayer

+ (EnvLayer *)layerWithId:(NSString *)layerId
					 name:(NSString *)name
				  enabled:(BOOL)enabled
				 priority:(NSInteger)priority
					  ops:(NSArray<EnvVarOp *> *)ops
{
	EnvLayer *layer = [EnvLayer new];
	layer->_layerId = [layerId copy];
	layer->_name = [name copy];
	layer->_enabled = enabled;
	layer->_priority = priority;
	layer->_ops = [ops copy] ?: @[];
	return layer;
}

- (NSString *)layerId { return _layerId; }
- (NSString *)name { return _name; }
- (BOOL)enabled { return _enabled; }
- (NSInteger)priority { return _priority; }
- (NSArray<EnvVarOp *> *)ops { return _ops; }

+ (EnvLayer *)layerFromJsonObject:(NSDictionary *)obj error:(NSError **)error
{
	if (![obj isKindOfClass:[NSDictionary class]]) {
		if (error) *error = [NSError errorWithDomain:@"EnvMask" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Layer JSON is not a dictionary"}];
		return nil;
	}

	NSString *layerId = obj[@"id"];
	NSString *name = obj[@"name"] ?: layerId;
	NSNumber *enabled = obj[@"enabled"] ?: @YES;
	NSNumber *priority = obj[@"priority"] ?: @10;
	NSDictionary *vars = obj[@"vars"] ?: @{};

	if (![layerId isKindOfClass:[NSString class]] || [layerId length] == 0) {
		if (error) *error = [NSError errorWithDomain:@"EnvMask" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Layer id missing"}];
		return nil;
	}
	if (![vars isKindOfClass:[NSDictionary class]]) {
		if (error) *error = [NSError errorWithDomain:@"EnvMask" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Layer vars must be a dictionary"}];
		return nil;
	}

	NSMutableArray<EnvVarOp *> *ops = [NSMutableArray array];
	for (NSString *key in vars) {
		id val = vars[key];
		if ([key isEqualToString:@"REMOVE"]) {
			if ([val isKindOfClass:[NSArray class]]) {
				for (id item in (NSArray *)val) {
					if ([item isKindOfClass:[NSString class]] && [item length] > 0) {
						[ops addObject:[EnvVarOp removeOpWithKey:(NSString *)item]];
					}
				}
			} else if ([val isKindOfClass:[NSString class]]) {
				NSArray *parts = [(NSString *)val componentsSeparatedByString:@","];
				for (NSString *p in parts) {
					NSString *trim = [p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
					if ([trim length] > 0) {
						[ops addObject:[EnvVarOp removeOpWithKey:trim]];
					}
				}
			}
			continue;
		}

		if (![val isKindOfClass:[NSString class]]) {
			// Skip non-string values to keep v1 simple/deterministic
			continue;
		}

		if ([key hasSuffix:@"+"]) {
			NSString *baseKey = [key substringToIndex:[key length] - 1];
			if ([baseKey length] > 0) {
				[ops addObject:[EnvVarOp appendPathOpWithKey:baseKey value:(NSString *)val]];
			}
		} else {
			[ops addObject:[EnvVarOp setOpWithKey:key value:(NSString *)val]];
		}
	}

	return [EnvLayer layerWithId:layerId
							name:name
						 enabled:[enabled boolValue]
						priority:[priority integerValue]
							 ops:ops];
}

+ (NSDictionary *)toJsonObjectFromLayer:(EnvLayer *)layer
{
	NSMutableDictionary *vars = [NSMutableDictionary dictionary];
	NSMutableArray *removes = [NSMutableArray array];

	for (EnvVarOp *op in layer.ops) {
		switch (op.type) {
			case EnvVarOpTypeSet:
				vars[op.key] = op.value ?: @"";
				break;
			case EnvVarOpTypeAppendPath:
				vars[[NSString stringWithFormat:@"%@+", op.key]] = op.value ?: @"";
				break;
			case EnvVarOpTypeRemove:
				if (op.key) [removes addObject:op.key];
				break;
		}
	}

	if ([removes count] > 0) {
		vars[@"REMOVE"] = removes;
	}

	return @{
		@"id": layer.layerId ?: @"",
		@"name": layer.name ?: layer.layerId ?: @"",
		@"enabled": @(layer.enabled),
		@"priority": @(layer.priority),
		@"vars": vars
	};
}

@end

