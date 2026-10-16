#import "Diagnostics.h"

void BNELogDiagnostic(NSString *message) {
    if (message.length == 0) return;
    NSLog(@"[BedrockNetworkESP_Lab] %@", message);
}