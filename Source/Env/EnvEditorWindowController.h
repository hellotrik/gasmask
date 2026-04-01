/***************************************************************************
 * EnvEditorWindowController
 *
 * Responsibilities:
 * - Provide a lightweight editor for EnvMask v1 data files.
 * - Tabs:
 *   - Layers: edit `layers.json`
 *   - Targets: edit `targets.json`
 *   - Preview: show resolved environment and active.zsh path
 *
 * Rationale:
 * - v1 prioritizes maintainability and fast iteration without adding xib.
 ***************************************************************************/

#import <Cocoa/Cocoa.h>

@interface EnvEditorWindowController : NSWindowController

+ (EnvEditorWindowController *)defaultInstance;
- (void)show;

@end

