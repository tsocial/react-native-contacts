#import <UIKit/UIKit.h>
#import "RCTContacts.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import "APAddressBook.h"
#import "APContact.h"
#import <AddressBook/AddressBook.h>

@implementation RCTContacts

RCT_EXPORT_MODULE();

- (NSDictionary *)constantsToExport
{
    return @{
             @"PERMISSION_DENIED": @"denied",
             @"PERMISSION_AUTHORIZED": @"authorized",
             @"PERMISSION_UNDEFINED": @"undefined"
             };
}

RCT_EXPORT_METHOD(checkPermission:(RCTResponseSenderBlock) callback)
{
    switch([APAddressBook access])
    {
        case APAddressBookAccessUnknown:
            callback(@[[NSNull null], @"undefined"]);
            break;
            
        case APAddressBookAccessGranted:
            callback(@[[NSNull null], @"authorized"]);
            break;
            
        case APAddressBookAccessDenied:
            callback(@[[NSNull null], @"denied"]);
            break;
    }
}

RCT_EXPORT_METHOD(requestPermission:(RCTResponseSenderBlock) callback)
{
    APAddressBook *addressBook = [[APAddressBook alloc] init];
    [addressBook requestAccess:^(BOOL granted, NSError *error)
     {
         [self checkPermission:callback];
     }];
}

RCT_EXPORT_METHOD(getAll:(RCTResponseSenderBlock) callback)
{
    [self getAllContacts:callback];
}

RCT_EXPORT_METHOD(getBatch: (NSUInteger)batchSize lastModificationDate: (NSUInteger) modificationDate callback :(RCTResponseSenderBlock) callback)
{
    NSDate *modificaftionDateTime = [NSDate dateWithTimeIntervalSince1970:modificationDate];
    
    [self getAllContacts:callback batchSize: batchSize filter: ^BOOL(APContact *contact) {
        NSDate *curModDate = contact.recordDate.modificationDate;
        if (curModDate) {
            return [curModDate compare:modificaftionDateTime] == NSOrderedDescending;
        } else {
            return false;
        }
    }];
}

RCT_EXPORT_METHOD(updateContact:(NSDictionary *)contactData callback:(RCTResponseSenderBlock)callback)
{
    NSString* recordID = [contactData valueForKey:@"recordID"];
    
    ABAddressBookRef addressBookRef = ABAddressBookCreateWithOptions(NULL, nil);
    ABRecordRef recordRef = ABAddressBookGetPersonWithRecordID(addressBookRef, recordID.intValue);
    
    ABRecordCopyValue(recordRef, kABPersonPhoneProperty);
    
    ABMutableMultiValueRef multiPhone = ABMultiValueCreateMutable(kABMultiStringPropertyType);
    for (id phoneData in [contactData valueForKey:@"phoneNumbers"]) {
        NSString *label = [phoneData valueForKey:@"label"];
        NSString *number = [phoneData valueForKey:@"number"];
        
        CFStringRef phoneLabel = CFBridgingRetain(label);
        
        if ([label isEqual: @"main"]){
            phoneLabel = kABPersonPhoneMainLabel;
        }
        else if ([label isEqual: @"mobile"]){
            phoneLabel = kABPersonPhoneMobileLabel;
        }
        else if ([label isEqual: @"iPhone"]){
            phoneLabel = kABPersonPhoneIPhoneLabel;
        }
        else {
            phoneLabel = CFBridgingRetain(label);
        }
        ABMultiValueAddValueAndLabel(multiPhone, CFBridgingRetain(number), phoneLabel, NULL);
    }
    
    ABRecordSetValue(recordRef, kABPersonPhoneProperty, multiPhone, nil);
    
    CFErrorRef saveError = NULL;
    if (ABAddressBookHasUnsavedChanges(addressBookRef)) {
        ABAddressBookSave(addressBookRef, &saveError);
    }
    
    callback(@[[NSNull null], [NSNull null]]);
}

// MARK: - My Privates
-(void) getAllContacts:(RCTResponseSenderBlock)callback batchSize: (NSUInteger)size filter:(BOOL (^)(APContact *))filterBlock
{
    APAddressBook *addressBook = [[APAddressBook alloc] init];
    
    addressBook.sortDescriptors = @[
                                    [NSSortDescriptor sortDescriptorWithKey:@"recordDate.modificationDate" ascending:YES]
                                    ];
    
    addressBook.filterBlock = filterBlock;
    
    [addressBook setFieldsMask: (APContactFieldName | APContactFieldPhonesOnly | APContactFieldThumbnail | APContactFieldRecordDate)];
    [addressBook loadContacts:^(NSArray<APContact *> * _Nullable contacts, NSError * _Nullable error) {
        NSMutableArray *contactDicts = [[NSMutableArray alloc] init];
        
        [contacts enumerateObjectsUsingBlock:^(APContact * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary *contactDictionary = [self contactToDictionary:obj retainPhoneAndAddressLabel: NO];
            [contactDicts addObject:contactDictionary];
        }];
        
        NSInteger count = MIN(contactDicts.count, size);
        NSArray *batchContactDicts = [contactDicts subarrayWithRange:NSMakeRange(0, count)];
        
        callback(@[[NSNull null], batchContactDicts]);
    }];
}

-(void) getAllContacts:(RCTResponseSenderBlock)callback
{
    APAddressBook *addressBook = [[APAddressBook alloc] init];
    
    addressBook.sortDescriptors = @[
                                    [NSSortDescriptor sortDescriptorWithKey:@"recordDate.modificationDate" ascending:YES]
                                    ];
    
    [addressBook setFieldsMask: (APContactFieldName | APContactFieldPhonesOnly | APContactFieldThumbnail | APContactFieldRecordDate)];
    [addressBook loadContacts:^(NSArray<APContact *> * _Nullable contacts, NSError * _Nullable error) {
        NSMutableArray *contactDicts = [[NSMutableArray alloc] init];
        
        [contacts enumerateObjectsUsingBlock:^(APContact * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary *contactDictionary = [self contactToDictionary:obj retainPhoneAndAddressLabel: YES];
            [contactDicts addObject:contactDictionary];
        }];
        
        callback(@[[NSNull null], contactDicts]);
    }];
}

-(NSDictionary*) contactToDictionary:(APContact *) person retainPhoneAndAddressLabel:(BOOL) retainLabel
{
    NSMutableDictionary* output = [NSMutableDictionary dictionary];
    
    NSString *recordID = [person.recordID stringValue];
    NSString *name = person.name.compositeName;
    NSDate *modDate = person.recordDate.modificationDate;
    NSTimeInterval modTimestamp = [modDate timeIntervalSince1970];
    NSNumber *modTimestampNumber = [[NSNumber alloc] initWithDouble: modTimestamp];
    
    [output setObject: recordID forKey: @"recordID"];
    [output setObject: modTimestampNumber forKey:@"modificationTimestamp"];
    
    if (name) {
        [output setObject: (name) ? name : @"" forKey:@"compositeName"];
    }
    
    NSMutableArray *phoneNumbers = [[NSMutableArray alloc] init];
    NSMutableArray *emails = [[NSMutableArray alloc] init];

    if (retainLabel) {
        for (APPhone *phone in person.phones) {
            NSMutableDictionary* phoneDict = [NSMutableDictionary dictionary];
            NSString* value = phone.number;
            
            if(value) {
                [phoneNumbers addObject:value];
            }
        }
        
        for (APEmail *email in person.emails) {
            NSMutableDictionary* emailDict = [NSMutableDictionary dictionary];
            NSString* value = email.address;
            
            if(value) {
                [emails addObject:value];
            }
        }
    } else {
        for (APPhone *phone in person.phones) {
            NSMutableDictionary* phoneDict = [NSMutableDictionary dictionary];
            NSString* label = phone.localizedLabel;
            NSString* value = phone.number;
            
            if(value) {
                if (value) {
                    [phoneDict setObject: value forKey:@"number"];
                }
                if (label) {
                    [phoneDict setObject: label forKey:@"label"];
                }
                [phoneNumbers addObject:phoneDict];
            }
        }

        for (APEmail *email in person.emails) {
            NSMutableDictionary* emailDict = [NSMutableDictionary dictionary];
            NSString* label = email.localizedLabel;
            NSString* value = email.address;
            
            if(value) {
                if (value) {
                    [emailDict setObject: value forKey:@"email"];
                }
                if (label) {
                    [emailDict setObject: label forKey:@"label"];
                }
                [emails addObject:emailDict];
            }
        }
    }

    [output setObject: phoneNumbers forKey:@"phoneNumbers"];
    [output setObject: emails forKey:@"emailAddresses"];
    
    return output;
}

@end
