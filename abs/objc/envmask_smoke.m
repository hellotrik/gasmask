/***************************************************************************
 * EnvMask smoke test (dev utility)
 *
 * Purpose:
 * - Verify EnvStore -> EnvResolver -> EnvExporter pipeline without launching UI.
 *
 * Build (example):
 * clang -fobjc-arc -framework Foundation -framework AppKit -I Source/Env \
 *   abs/objc/envmask_smoke.m Source/Env/EnvLayer.m Source/Env/EnvResolver.m Source/Env/EnvStore.m Source/Env/EnvExporter.m \
 *   -o /tmp/envmask_smoke
 ***************************************************************************/

#import <Foundation/Foundation.h>

#import "EnvStore.h"
#import "EnvResolver.h"
#import "EnvExporter.h"

int main(int argc, const char * argv[]) {
	@autoreleasepool {
		EnvStore *store = [EnvStore defaultInstance];
		NSArray<EnvLayer *> *layers = [store loadLayers];
		NSDictionary<NSString *, NSString *> *env = [EnvResolver resolveFromLayers:layers];

		NSError *err = nil;
		BOOL ok = [EnvExporter writeActiveZshFromEnv:env error:&err];
		if (!ok) {
			fprintf(stderr, "writeActiveZsh failed: %s\n", [[err description] UTF8String]);
			return 2;
		}

		printf("store=%s\n", [[store rootDirectory] UTF8String]);
		printf("activeZsh=%s\n", [[EnvExporter activeZshPath] UTF8String]);
		printf("vars=%lu\n", (unsigned long)[[env allKeys] count]);
	}
	return 0;
}

