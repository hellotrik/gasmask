#import <Foundation/Foundation.h>
#import "EnvLayer.h"

/// 纯文本 ⇄ EnvVarOp 列表（类 hosts：一行一条，无弹窗编辑）。
@interface EnvOpsTextFormat : NSObject

+ (NSString *)textFromOps:(NSArray<EnvVarOp *> *)ops;

+ (NSArray<EnvVarOp *> *)opsFromText:(NSString *)text;

@end
