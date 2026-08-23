#import <Foundation/Foundation.h>
extern "C" NSUInteger prismel_mtl_compute_command_mechanical_id_count(void);
int main(void){@autoreleasepool{if(prismel_mtl_compute_command_mechanical_id_count()!=22)return 1;
NSLog(@"compute command103: 22 typed mechanical IDs compiled");return 0;}}
