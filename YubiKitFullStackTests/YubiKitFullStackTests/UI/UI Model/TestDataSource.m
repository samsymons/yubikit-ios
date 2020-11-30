//
//  TestDataSource.m
//  YubiKitFullStackTests
//
//  Created by Conrad Ciobanica on 2018-05-16.
//  Copyright © 2018 Yubico. All rights reserved.
//
#import "TestDataSource.h"
#import "TestSharedLogger.h"
#import "GnubbySelectU2FApplicationAPDU.h"

@interface TestDataSource()<UITableViewDataSource>

@property (nonatomic) UITableView *tableView;
@property (nonatomic, readonly) YKFAccessoryConnection *accessorySession;

@end

@implementation TestDataSource

- (instancetype)initWithTableView:(UITableView *)tableView {
    NSParameterAssert(tableView);
    self = [super init];
    if (self) {
        self.testDataGenerator = [[TestDataGenerator alloc] init];
        
        [self setupTestList];
        
        self.tableView = tableView;
        self.tableView.dataSource = self;
    }
    return self;
}

- (void)executeTestEntryAtIndexPath:(nonnull NSIndexPath*)indexPath {
    NSArray *testEntry = self.testList[indexPath.section][1][indexPath.row];

    NSString *testName = testEntry[0];
    SEL testSelector = [((NSValue *)testEntry[2]) pointerValue];
    
    [TestSharedLogger.shared logMessage:@"Starting test: %@ ...", testName];
    [TestSharedLogger.shared logSepparator];
    
    __weak typeof(self) weakSelf = self;
    
    dispatch_queue_t dispatchQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatchQueue, ^{
        __strong typeof(self) strongSelf = weakSelf;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [strongSelf performSelector:testSelector];
#pragma clang diagnostic pop
    });
}

- (YKFAccessoryConnection *)accessorySession {
    return (YKFAccessoryConnection *)YubiKitManager.shared.accessorySession;
}

#pragma mark - UITableViewDataSource

- (nonnull UITableViewCell *)tableView:(nonnull UITableView *)tableView cellForRowAtIndexPath:(nonnull NSIndexPath *)indexPath {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"ManualTestCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ManualTestCell"];
    }
    
    NSArray *testEntry = self.testList[indexPath.section][1][indexPath.row];
    NSAssert(testEntry.count == 3, @"Invalid test entry. Must have all the fields defined.");
    
    NSAssert([testEntry[0] isKindOfClass:NSString.class], @"Invalid test name.");
    NSString *testName = testEntry[0];
    NSAssert(testName.length > 0, @"Test name is empty.");
    
    NSAssert([testEntry[1] isKindOfClass:NSString.class], @"Invalid test description.");
    NSString *testDescription = testEntry[1];
    NSAssert(testDescription.length > 0, @"Tests description is empty. Add a short description for the test.");
    
    cell.textLabel.text = testName;
    cell.detailTextLabel.text = testDescription;
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.testList[section][0];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.testList.count;
}

- (NSInteger)tableView:(nonnull UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return ((NSArray *)self.testList[section][1]).count;
}

#pragma mark - Command execution

- (void)executeManagementApplicationSelection {
    NSData *data = [NSData dataWithBytes:(UInt8[]){0xA0, 0x00, 0x00, 0x05, 0x27, 0x47, 0x11, 0x17} length:8];
    YKFSelectApplicationAPDU *apdu = [[YKFSelectApplicationAPDU alloc] initWithData:data];
    [self executeApplicationSelection:apdu];
}

- (void)executeU2FApplicationSelection {
    NSData *data = [NSData dataWithBytes:(UInt8[]){0xA0, 0x00, 0x00, 0x06, 0x47, 0x2F, 0x00, 0x01} length:8];
    YKFSelectApplicationAPDU *apdu = [[YKFSelectApplicationAPDU alloc] initWithData:data];
    [self executeApplicationSelection:apdu];
}

- (void)executeGnubbyU2FApplicationSelection {
    NSData *data = [NSData dataWithBytes:(UInt8[]){0xA0, 0x00, 0x00, 0x05, 0x27, 0x10, 0x02, 0x01} length:8];
    YKFSelectApplicationAPDU *apdu = [[YKFSelectApplicationAPDU alloc] initWithData:data];
    [self executeApplicationSelection:apdu];
}

- (void)executeYubiKeyApplicationSelection {
    
    
    
    NSData *data = [NSData dataWithBytes:(UInt8[]){0xA0, 0x00, 0x00, 0x05, 0x27, 0x20, 0x01, 0x01} length:8];
    YKFSelectApplicationAPDU *apdu = [[YKFSelectApplicationAPDU alloc] initWithData:data];
    [self executeApplicationSelection:apdu];
}

- (void)executePivApplicationSelection {
//    0x00, 0xA4, 0x04, 0x00, 0x05, 0xA0, 0x00, 0x00, 0x03, 0x08
    NSData *data = [NSData dataWithBytes:(UInt8[]){0xA0, 0x00, 0x00, 0x03, 0x08} length:5];
    YKFSelectApplicationAPDU *apdu = [[YKFSelectApplicationAPDU alloc] initWithData:data];
    [self executeApplicationSelection:apdu];
}

- (void)executeApplicationSelection:(YKFSelectApplicationAPDU *)apdu {
    __weak typeof(self) weakSelf = self;
    [self.connection.smartCardInterface selectApplication:apdu completion:^(NSData * _Nullable data, NSError * _Nullable error) {
        __strong typeof(self) strongSelf = weakSelf;
        if (error) {
            [TestSharedLogger.shared logError: @"Application selection failed with error: %@", error.localizedDescription];
            // Cancel all queued commands
            [strongSelf.accessorySession cancelCommands];
        } else {
            [TestSharedLogger.shared logMessage: @"Application selected"];
        }
    }];
}

- (void)executeCommandWithAPDU:(YKFAPDU *)apdu completion:(YKFKeySmartCardInterfaceResponseBlock)completion {
    [self.accessorySession.smartCardInterface executeCommand:apdu completion:completion];
}

- (void)executeCommandWithData:(NSData *)data completion:(YKFKeySmartCardInterfaceResponseBlock)completion {
    YKFAPDU *apdu = [[YKFAPDU alloc] initWithData:data];
    [self executeCommandWithAPDU:apdu completion:completion];
}

#pragma mark - Test setup

- (void)setupTestList {
    NSAssert(NO, @"setupTestList must be overridden in the base subclass.");
}

@end
