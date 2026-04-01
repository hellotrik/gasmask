/***************************************************************************
 * EnvLayer
 *
 * Responsibilities:
 * - Represents a single “layer” of environment variable configuration.
 * - Stores enable/disable state and priority (merge order).
 * - Holds a list of variable operations (set/appendPath/remove).
 *
 * Design notes:
 * - We avoid tying this to shell syntax; exporter handles shell escaping.
 * - Merge semantics are deterministic: enabled layers sorted by priority,
 *   then applied in order; later operations win.
 *
 * Threading:
 * - Immutable-ish value object once created; safe to read across threads.
 ***************************************************************************/

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, EnvVarOpType) {
	EnvVarOpTypeSet = 0,
	EnvVarOpTypeAppendPath = 1,
	EnvVarOpTypeRemove = 2
};

@interface EnvVarOp : NSObject

@property (nonatomic, readonly) EnvVarOpType type;
@property (nonatomic, readonly) NSString *key;
@property (nonatomic, readonly) NSString *value; // nil for remove

+ (EnvVarOp *)setOpWithKey:(NSString *)key value:(NSString *)value;
+ (EnvVarOp *)appendPathOpWithKey:(NSString *)key value:(NSString *)value;
+ (EnvVarOp *)removeOpWithKey:(NSString *)key;

@end

@interface EnvLayer : NSObject

@property (nonatomic, readonly) NSString *layerId;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) NSInteger priority;
@property (nonatomic, readonly) NSArray<EnvVarOp *> *ops;

+ (EnvLayer *)layerWithId:(NSString *)layerId
					 name:(NSString *)name
				  enabled:(BOOL)enabled
				 priority:(NSInteger)priority
					  ops:(NSArray<EnvVarOp *> *)ops;

/// JSON shape (v1):
/// {
///   "id": "base",
///   "name": "base",
///   "enabled": true,
///   "priority": 10,
///   "vars": {
///     "JAVA_HOME": "/Library/Java/...",
///     "PATH+": "/opt/homebrew/bin",
///     "REMOVE": ["HTTP_PROXY"]
///   }
/// }
+ (EnvLayer *)layerFromJsonObject:(NSDictionary *)obj error:(NSError **)error;
+ (NSDictionary *)toJsonObjectFromLayer:(EnvLayer *)layer;

@end

