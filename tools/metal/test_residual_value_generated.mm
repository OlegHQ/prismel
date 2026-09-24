#import <Foundation/Foundation.h>
extern "C" NSUInteger prismel_mtl_residual_mechanical_id_count(void);
int main(void){@autoreleasepool{if(prismel_mtl_residual_mechanical_id_count()!=32)return 1;
NSLog(@"final residual87: 32 typed mechanical IDs compiled");return 0;}}
