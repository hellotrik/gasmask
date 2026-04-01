/***************************************************************************
 * EnvResolver implementation
 ***************************************************************************/

#import "EnvResolver.h"

@implementation EnvResolver

+ (NSArray<EnvLayer *> *)enabledLayersSorted:(NSArray<EnvLayer *> *)layers
{
	NSArray<EnvLayer *> *enabled = [layers filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(EnvLayer *layer, NSDictionary *bindings) {
		return layer.enabled;
	}]];

	return [enabled sortedArrayUsingComparator:^NSComparisonResult(EnvLayer *a, EnvLayer *b) {
		if (a.priority < b.priority) return NSOrderedAscending;
		if (a.priority > b.priority) return NSOrderedDescending;
		// deterministic tie-breakers
		NSComparisonResult byName = [a.name compare:b.name options:NSCaseInsensitiveSearch];
		if (byName != NSOrderedSame) return byName;
		return [a.layerId compare:b.layerId options:NSCaseInsensitiveSearch];
	}];
}

+ (NSDictionary<NSString *, NSString *> *)resolveFromLayers:(NSArray<EnvLayer *> *)layers
{
	NSMutableDictionary<NSString *, NSString *> *env = [NSMutableDictionary dictionary];

	for (EnvLayer *layer in [self enabledLayersSorted:layers]) {
		for (EnvVarOp *op in layer.ops) {
			if ([op.key length] == 0) {
				continue;
			}
			switch (op.type) {
				case EnvVarOpTypeSet: {
					env[op.key] = op.value ?: @"";
					break;
				}
				case EnvVarOpTypeAppendPath: {
					NSString *existing = env[op.key];
					NSString *append = op.value ?: @"";
					if ([append length] == 0) break;
					if ([existing length] == 0) {
						env[op.key] = append;
					} else {
						env[op.key] = [NSString stringWithFormat:@"%@:%@", existing, append];
					}
					break;
				}
				case EnvVarOpTypeRemove: {
					[env removeObjectForKey:op.key];
					break;
				}
			}
		}
	}

	return env;
}

@end

