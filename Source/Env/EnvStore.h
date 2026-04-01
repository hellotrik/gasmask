/***************************************************************************
 * EnvStore
 *
 * Responsibilities:
 * - Persist layers & targets under ~/Library/Env Mask/
 * - Provide atomic load/save and create defaults on first run.
 *
 * Files (v1):
 * - layers.json: [layer...]
 * - targets.json: [target...]
 ***************************************************************************/

#import <Foundation/Foundation.h>
#import "EnvLayer.h"

@interface EnvTarget : NSObject

@property (nonatomic, readonly) NSString *targetId;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *executablePath; // e.g. Foo.app/.../MacOS/Foo or /usr/local/bin/foo
@property (nonatomic, readonly) NSArray<NSString *> *layerIds; // which layers to apply (optional; empty => current enabled)

+ (EnvTarget *)targetWithId:(NSString *)targetId
					   name:(NSString *)name
			 executablePath:(NSString *)executablePath
				   layerIds:(NSArray<NSString *> *)layerIds;

+ (EnvTarget *)targetFromJsonObject:(NSDictionary *)obj error:(NSError **)error;
+ (NSDictionary *)toJsonObjectFromTarget:(EnvTarget *)target;

@end

@interface EnvStore : NSObject

+ (EnvStore *)defaultInstance;

- (NSString *)rootDirectory;
- (NSString *)layersFilePath;
- (NSString *)targetsFilePath;

- (NSArray<EnvLayer *> *)loadLayers;
- (BOOL)saveLayers:(NSArray<EnvLayer *> *)layers error:(NSError **)error;

/// Ensure a Temp layer exists (id = "temp") and return updated layers.
- (NSArray<EnvLayer *> *)ensureTempLayerExists;

/// Upsert one variable op into Temp layer (set/append/remove) and persist.
- (NSArray<EnvLayer *> *)upsertTempOpWithType:(EnvVarOpType)type key:(NSString *)key value:(NSString *)value;

/// Remove all ops in Temp layer and persist.
- (NSArray<EnvLayer *> *)clearTempLayerOps;

- (NSArray<EnvTarget *> *)loadTargets;
- (BOOL)saveTargets:(NSArray<EnvTarget *> *)targets error:(NSError **)error;

/// Toggle layer enabled state and persist.
- (NSArray<EnvLayer *> *)toggleLayerEnabledById:(NSString *)layerId;

@end

