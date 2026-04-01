/***************************************************************************
 * EnvExporter
 *
 * Responsibilities:
 * - Export resolved environment as a shell script (zsh/bash compatible).
 * - Provide stable active file path for user to `source`.
 ***************************************************************************/

#import <Foundation/Foundation.h>

@interface EnvExporter : NSObject

+ (NSString *)activeShellDirectory;   // ~/.envmask
+ (NSString *)activeZshPath;          // ~/.envmask/active.zsh

+ (NSString *)formatZshExportScriptFromEnv:(NSDictionary<NSString *, NSString *> *)env;
+ (BOOL)writeActiveZshFromEnv:(NSDictionary<NSString *, NSString *> *)env error:(NSError **)error;

+ (void)openActiveZshInFinder;
+ (void)copySourceCommandToPasteboard;

/// Terminal auto-apply (zsh) support:
/// - Adds/removes a single managed line to ~/.zshrc
/// - If Cursor terminal profiles set ZDOTDIR, also installs into $ZDOTDIR/.zshrc
/// - Keeps a backup at ~/.zshrc.envmask.bak (best-effort)
+ (BOOL)isZshrcInstalled;
+ (BOOL)installToZshrc:(NSError **)error;
+ (BOOL)uninstallFromZshrc:(NSError **)error;

@end

