/***************************************************************************
 * EnvResolver
 *
 * Responsibilities:
 * - Merge enabled layers into a resolved environment dictionary.
 * - Provide deterministic ordering and predictable PATH append semantics.
 *
 * Merge rules:
 * - Only enabled layers participate.
 * - Sort by priority ascending (stable by name/id).
 * - Apply ops in order:
 *   - Set: overwrite key
 *   - AppendPath: append with ':' (if existing non-empty)
 *   - Remove: remove key
 ***************************************************************************/

#import <Foundation/Foundation.h>
#import "EnvLayer.h"

@interface EnvResolver : NSObject

+ (NSDictionary<NSString *, NSString *> *)resolveFromLayers:(NSArray<EnvLayer *> *)layers;
+ (NSArray<EnvLayer *> *)enabledLayersSorted:(NSArray<EnvLayer *> *)layers;

@end

