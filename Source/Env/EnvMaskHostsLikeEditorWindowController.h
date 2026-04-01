/***************************************************************************
 * EnvMaskHostsLikeEditorWindowController
 *
 * Responsibilities:
 * - Host-like editor window: left SourceList (Profiles/Temp), right editor.
 * - Provide toolbar-style actions: Create/Remove/Enable/Save/ApplyToTerminal.
 *
 * Notes:
 * - Mirrors Gas Mask’s mental model but keeps multi-enable semantics.
 ***************************************************************************/

#import <Cocoa/Cocoa.h>

@interface EnvMaskHostsLikeEditorWindowController : NSWindowController

+ (EnvMaskHostsLikeEditorWindowController *)defaultInstance;
- (void)show;

@end

