/***************************************************************************
 * EnvMaskController
 *
 * Responsibilities:
 * - Glue layer store + resolver + exporter into menu actions.
 * - Provide dynamic NSMenu for the status bar (Gas Mask style).
 ***************************************************************************/

#import <Foundation/Foundation.h>

@class NSMenu;

@interface EnvMaskController : NSObject

+ (EnvMaskController *)defaultInstance;

- (NSMenu *)createEnvMaskSubmenu;

// Actions
- (void)toggleLayerFromMenuItem:(id)sender;
- (void)clearTempVariables:(id)sender;
- (void)installTerminalAutoApply:(id)sender;
- (void)uninstallTerminalAutoApply:(id)sender;
- (void)exportActiveZsh:(id)sender;
- (void)copySourceCommand:(id)sender;
- (void)openActiveZsh:(id)sender;
- (void)openEnvEditor:(id)sender;

@end

