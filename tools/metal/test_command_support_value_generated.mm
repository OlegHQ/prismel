#import <Foundation/Foundation.h>
extern "C" NSUInteger prismel_mtl_command_support_mechanical_id_count(void);
int main(void){@autoreleasepool{if(prismel_mtl_command_support_mechanical_id_count()!=27)return 1;
NSLog(@"command support121: 27 typed mechanical IDs compiled");return 0;}}
