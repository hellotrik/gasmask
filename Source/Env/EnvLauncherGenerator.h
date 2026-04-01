/***************************************************************************
 * EnvLauncherGenerator
 *
 * Responsibilities:
 * - Generate per-app launch scripts (.command) that execute a target binary
 *   with a resolved environment.
 *
 * Notes:
 * - `open` does not allow passing env reliably; we exec the actual binary.
 * - This is intentionally simple for v1; a future v2 can generate a tiny
 *   launcher .app bundle.
 ***************************************************************************/

#import <Foundation/Foundation.h>

@interface EnvLauncherGenerator : NSObject

+ (NSString *)launchersDirectoryInStore; // ~/Library/Env Mask/Launchers
+ (BOOL)ensureLaunchersDirectoryExists:(NSError **)error;

/// Generates a `.command` script and returns its path.
+ (NSString *)createCommandLauncherWithName:(NSString *)name
							 executablePath:(NSString *)executablePath
										env:(NSDictionary<NSString *, NSString *> *)env
									  error:(NSError **)error;

@end

