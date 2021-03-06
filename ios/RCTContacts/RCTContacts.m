#import <AddressBook/AddressBook.h>
#import <UIKit/UIKit.h>
#import "RCTContacts.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import "APAddressBook.h"
#import "APContact.h"
#import "NBPhoneNumberUtil.h"
#import "NBPhoneNumber.h"

@interface RCTContacts() <CNContactPickerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) RCTPromiseResolveBlock resolve;
@property (nonatomic, strong) RCTPromiseRejectBlock reject;

@end
@implementation RCTContacts {
    CNContactStore * contactStore;
}

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
    CNAuthorizationStatus authStatus = [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts];
    if (authStatus == CNAuthorizationStatusDenied || authStatus == CNAuthorizationStatusRestricted){
        callback(@[[NSNull null], @"denied"]);
    } else if (authStatus == CNAuthorizationStatusAuthorized){
        callback(@[[NSNull null], @"authorized"]);
    } else {
        callback(@[[NSNull null], @"undefined"]);
    }
}

RCT_EXPORT_METHOD(requestPermission:(RCTResponseSenderBlock) callback)
{
    CNContactStore* contactStore = [[CNContactStore alloc] init];
    
    [contactStore requestAccessForEntityType:CNEntityTypeContacts completionHandler:^(BOOL granted, NSError * _Nullable error) {
        [self checkPermission:callback];
    }];
}

RCT_EXPORT_METHOD(getContactsMatchingString:(NSString *)string callback:(RCTResponseSenderBlock) callback)
{
    CNContactStore *contactStore = [[CNContactStore alloc] init];
    if (!contactStore)
        return;
    [self getContactsFromAddressBook:contactStore matchingString:string callback:callback];
}

-(void) getContactsFromAddressBook:(CNContactStore *)store
                    matchingString:(NSString *)searchString
                          callback:(RCTResponseSenderBlock)callback
{
    NSMutableArray *contacts = [[NSMutableArray alloc] init];
    NSError *contactError = nil;
    NSArray *keys = @[
                      CNContactEmailAddressesKey,
                      CNContactPhoneNumbersKey,
                      CNContactFamilyNameKey,
                      CNContactGivenNameKey,
                      CNContactMiddleNameKey,
                      CNContactPostalAddressesKey,
                      CNContactOrganizationNameKey,
                      CNContactJobTitleKey,
                      CNContactImageDataAvailableKey,
                      CNContactBirthdayKey
                      ];
    NSArray *arrayOfContacts = [store unifiedContactsMatchingPredicate:[CNContact predicateForContactsMatchingName:searchString]
                                                           keysToFetch:keys
                                                                 error:&contactError];
    [arrayOfContacts enumerateObjectsUsingBlock:^(CNContact * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary *contactDictionary = [self contactToDictionary:obj withThumbnails:NO];
        [contacts addObject:contactDictionary];
    }];
    callback(@[[NSNull null], contacts]);
}

-(void) getAllContacts:(RCTResponseSenderBlock) callback
       withPhoneNumber:(NSString*) phoneNumber
        withThumbnails:(BOOL) withThumbnails
{
    CNContactStore* contactStore = [self contactsStore:callback];
    if(!contactStore)
        return;
    
    [self retrieveContactsFromAddressBook:contactStore
                            byPhoneNumber:phoneNumber
                           withThumbnails:withThumbnails
                             withCallback:callback];
}

RCT_EXPORT_METHOD(getAll:(RCTResponseSenderBlock) callback)
{
    [self getAllContacts:callback withPhoneNumber:nil withThumbnails:true];
}

RCT_EXPORT_METHOD(getAllWithoutPhotos:(RCTResponseSenderBlock) callback)
{
    [self getAllContacts:callback withPhoneNumber:nil withThumbnails:false];
}

RCT_EXPORT_METHOD(getByPhoneNumber:(NSString*) phoneNumber callback:(RCTResponseSenderBlock) callback)
{
    [self getAllContacts:callback withPhoneNumber:phoneNumber withThumbnails:true];
}

-(void) retrieveContactsFromAddressBook:(CNContactStore*) contactStore
                          byPhoneNumber:(NSString*) phoneNumber
                         withThumbnails:(BOOL) withThumbnails
                           withCallback:(RCTResponseSenderBlock) callback
{
    NSMutableArray *contacts = [[NSMutableArray alloc] init];
    
    NSError* contactError;
    [contactStore containersMatchingPredicate:[CNContainer predicateForContainersWithIdentifiers: @[contactStore.defaultContainerIdentifier]] error:&contactError];
    
    
    NSMutableArray *keysToFetch = [[NSMutableArray alloc]init];
    [keysToFetch addObjectsFromArray:@[
                                       CNContactEmailAddressesKey,
                                       CNContactPhoneNumbersKey,
                                       CNContactFamilyNameKey,
                                       CNContactGivenNameKey,
                                       CNContactMiddleNameKey,
                                       CNContactPostalAddressesKey,
                                       CNContactOrganizationNameKey,
                                       CNContactJobTitleKey,
                                       CNContactImageDataAvailableKey,
                                       CNContactBirthdayKey
                                       ]];
    
    if(withThumbnails) {
        [keysToFetch addObject:CNContactThumbnailImageDataKey];
    }
    
    CNContactFetchRequest * request = [[CNContactFetchRequest alloc]initWithKeysToFetch:keysToFetch];
    BOOL success = [contactStore enumerateContactsWithFetchRequest:request error:&contactError usingBlock:^(CNContact * __nonnull contact, BOOL * __nonnull stop){
        
        if (!phoneNumber) {
            NSDictionary *contactDict = [self contactToDictionary: contact withThumbnails:withThumbnails];
            [contacts addObject:contactDict];
        } else {
            for (CNLabeledValue<CNPhoneNumber*>* labeledValue in contact.phoneNumbers) {
                NSString* value = [[labeledValue value] stringValue];
                if(value) {
                    NSString *phone1 = [self toNationalFormat:value];
                    NSString *phone2 = [self toNationalFormat:phoneNumber];
                    
                    if ([phone1 isEqual: phone2]) {
                        NSDictionary *contactDict = [self contactToDictionary: contact withThumbnails:withThumbnails];
                        [contacts addObject:contactDict];
                        *stop = YES;
                        break;
                    }
                }
            }
        }
    }];
    
    callback(@[[NSNull null], contacts]);
}

-(NSString *) toNationalFormat: (NSString *)phoneNumber {
    NBPhoneNumberUtil *phoneUtil = [[NBPhoneNumberUtil alloc] init];
    NSError *anError = nil;
    NBPhoneNumber *myNumber = [phoneUtil parse:phoneNumber
                                 defaultRegion:@"VN" error:&anError];
    if (anError) {
        NSLog(@"Parse phone number failed - error: %@", [anError localizedDescription]);
    }
    return [myNumber.nationalNumber stringValue];
}

-(NSDictionary*) contactToDictionary:(CNContact *) person
                      withThumbnails:(BOOL)withThumbnails
{
    NSMutableDictionary* output = [NSMutableDictionary dictionary];
    
    NSString *recordID = person.identifier;
    NSString *givenName = person.givenName;
    NSString *familyName = person.familyName;
    NSString *middleName = person.middleName;
    NSString *company = person.organizationName;
    NSString *jobTitle = person.jobTitle;
    NSDateComponents *birthday = person.birthday;
    
    [output setObject:recordID forKey: @"recordID"];
    
    if (givenName) {
        [output setObject: (givenName) ? givenName : @"" forKey:@"givenName"];
        [output setObject: (givenName) ? givenName : @"" forKey:@"compositeName"];
    }
    
    if (familyName) {
        [output setObject: (familyName) ? familyName : @"" forKey:@"familyName"];
    }
    
    if(middleName){
        [output setObject: (middleName) ? middleName : @"" forKey:@"middleName"];
    }
    
    if(company){
        [output setObject: (company) ? company : @"" forKey:@"company"];
    }
    
    if(jobTitle){
        [output setObject: (jobTitle) ? jobTitle : @"" forKey:@"jobTitle"];
    }
    
    
    if (birthday) {
        if (birthday.month != NSDateComponentUndefined && birthday.day != NSDateComponentUndefined) {
            //months are indexed to 0 in JavaScript (0 = January) so we subtract 1 from NSDateComponents.month
            if (birthday.year != NSDateComponentUndefined) {
                [output setObject:@{@"year": @(birthday.year), @"month": @(birthday.month - 1), @"day": @(birthday.day)} forKey:@"birthday"];
            } else {
                [output setObject:@{@"month": @(birthday.month - 1), @"day":@(birthday.day)} forKey:@"birthday"];
            }
        }
    }
    
    //handle phone numbers
    NSMutableArray *phoneNumbers = [[NSMutableArray alloc] init];
    
    for (CNLabeledValue<CNPhoneNumber*>* labeledValue in person.phoneNumbers) {
        NSMutableDictionary* phone = [NSMutableDictionary dictionary];
        NSString * label = [CNLabeledValue localizedStringForLabel:[labeledValue label]];
        NSString* value = [[labeledValue value] stringValue];
        
        if(value) {
            if(!label) {
                label = [CNLabeledValue localizedStringForLabel:@"other"];
            }
            [phone setObject: value forKey:@"number"];
            [phone setObject: label forKey:@"label"];
            [phoneNumbers addObject:phone];
        }
    }
    
    [output setObject: phoneNumbers forKey:@"phoneNumbers"];
    //end phone numbers
    
    //handle emails
    NSMutableArray *emailAddreses = [[NSMutableArray alloc] init];
    
    for (CNLabeledValue<NSString*>* labeledValue in person.emailAddresses) {
        NSMutableDictionary* email = [NSMutableDictionary dictionary];
        NSString* label = [CNLabeledValue localizedStringForLabel:[labeledValue label]];
        NSString* value = [labeledValue value];
        
        if(value) {
            if(!label) {
                label = [CNLabeledValue localizedStringForLabel:@"other"];
            }
            [email setObject: value forKey:@"email"];
            [email setObject: label forKey:@"label"];
            [emailAddreses addObject:email];
        } else {
            NSLog(@"ignoring blank email");
        }
    }
    
    [output setObject: emailAddreses forKey:@"emailAddresses"];
    //end emails
    
    //handle postal addresses
    NSMutableArray *postalAddresses = [[NSMutableArray alloc] init];
    
    for (CNLabeledValue<CNPostalAddress*>* labeledValue in person.postalAddresses) {
        CNPostalAddress* postalAddress = labeledValue.value;
        NSMutableDictionary* address = [NSMutableDictionary dictionary];
        
        NSString* street = postalAddress.street;
        if(street){
            [address setObject:street forKey:@"street"];
        }
        NSString* city = postalAddress.city;
        if(city){
            [address setObject:city forKey:@"city"];
        }
        NSString* state = postalAddress.state;
        if(state){
            [address setObject:state forKey:@"state"];
        }
        NSString* region = postalAddress.state;
        if(region){
            [address setObject:region forKey:@"region"];
        }
        NSString* postCode = postalAddress.postalCode;
        if(postCode){
            [address setObject:postCode forKey:@"postCode"];
        }
        NSString* country = postalAddress.country;
        if(country){
            [address setObject:country forKey:@"country"];
        }
        
        NSString* label = [CNLabeledValue localizedStringForLabel:labeledValue.label];
        if(label) {
            [address setObject:label forKey:@"label"];
            
            [postalAddresses addObject:address];
        }
    }
    
    [output setObject:postalAddresses forKey:@"postalAddresses"];
    //end postal addresses
    
    [output setValue:[NSNumber numberWithBool:person.imageDataAvailable] forKey:@"hasThumbnail"];
    if (withThumbnails) {
        [output setObject:[self getFilePathForThumbnailImage:person recordID:recordID] forKey:@"thumbnailPath"];
    }
    
    return output;
}

- (NSString *)thumbnailFilePath:(NSString *)recordID
{
    NSString *filename = [recordID stringByReplacingOccurrencesOfString:@":ABPerson" withString:@""];
    NSString* filepath = [NSString stringWithFormat:@"%@/rncontacts_%@.png", [self getPathForDirectory:NSCachesDirectory], filename];
    return filepath;
}

-(NSString *) getFilePathForThumbnailImage:(CNContact*) contact recordID:(NSString*) recordID
{
    NSString *filepath = [self thumbnailFilePath:recordID];
    
    if([[NSFileManager defaultManager] fileExistsAtPath:filepath]) {
        return filepath;
    }
    
    if (contact.imageDataAvailable){
        NSData *contactImageData = contact.thumbnailImageData;
        
        BOOL success = [[NSFileManager defaultManager] createFileAtPath:filepath contents:contactImageData attributes:nil];
        
        if (!success) {
            NSLog(@"Unable to copy image");
            return @"";
        }
        
        return filepath;
    }
    
    return @"";
}

- (NSString *)getPathForDirectory:(int)directory
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(directory, NSUserDomainMask, YES);
    return [paths firstObject];
}

RCT_EXPORT_METHOD(getPhotoForId:(nonnull NSString *)recordID callback:(RCTResponseSenderBlock)callback)
{
    CNContactStore* contactStore = [self contactsStore:callback];
    if(!contactStore)
        return;
    
    CNEntityType entityType = CNEntityTypeContacts;
    if([CNContactStore authorizationStatusForEntityType:entityType] == CNAuthorizationStatusNotDetermined)
    {
        [contactStore requestAccessForEntityType:entityType completionHandler:^(BOOL granted, NSError * _Nullable error) {
            if(granted){
                callback(@[[NSNull null], [self getFilePathForThumbnailImage:recordID addressBook:contactStore]]);
            }
        }];
    }
    else if( [CNContactStore authorizationStatusForEntityType:entityType]== CNAuthorizationStatusAuthorized)
    {
        callback(@[[NSNull null], [self getFilePathForThumbnailImage:recordID addressBook:contactStore]]);
    }
}

-(NSString *) getFilePathForThumbnailImage:(NSString *)recordID
                               addressBook:(CNContactStore*)addressBook
{
    NSString *filepath = [self thumbnailFilePath:recordID];
    
    if([[NSFileManager defaultManager] fileExistsAtPath:filepath]) {
        return filepath;
    }
    
    NSError* contactError;
    NSArray * keysToFetch =@[CNContactThumbnailImageDataKey, CNContactImageDataAvailableKey];
    CNContact* contact = [addressBook unifiedContactWithIdentifier:recordID keysToFetch:keysToFetch error:&contactError];
    
    return [self getFilePathForThumbnailImage:contact recordID:recordID];
}


RCT_EXPORT_METHOD(addContact:(NSDictionary *)contactData callback:(RCTResponseSenderBlock)callback)
{
    CNContactStore* contactStore = [self contactsStore:callback];
    if(!contactStore)
        return;
    
    CNMutableContact * contact = [[CNMutableContact alloc] init];
    
    [self updateRecord:contact withData:contactData];
    
    @try {
        CNSaveRequest *request = [[CNSaveRequest alloc] init];
        [request addContact:contact toContainerWithIdentifier:nil];
        
        [contactStore executeSaveRequest:request error:nil];
        
        NSDictionary *contactDict = [self contactToDictionary:contact withThumbnails:false];
        
        callback(@[[NSNull null], contactDict]);
    }
    @catch (NSException *exception) {
        callback(@[[exception description], [NSNull null]]);
    }
}

//RCT_EXPORT_METHOD(openContactForm:(NSDictionary *)contactData isEdit:(BOOL)isEdit callback:(RCTResponseSenderBlock)callback)
RCT_EXPORT_METHOD(openContactForm:(NSDictionary *)contactData callback:(RCTResponseSenderBlock)callback)
{
    CNContactStore* contactStore = [self contactsStore:callback];
    if(!contactStore)
        return;
    
    CNContactViewController *controller;
    
    NSString *recordID = [contactData valueForKey:@"recordID"];
    NSArray * keysToFetch =@[CNContactViewController.descriptorForRequiredKeys];
    NSError* contactError;
    CNMutableContact* contact = [[contactStore unifiedContactWithIdentifier:recordID keysToFetch:keysToFetch error:&contactError] mutableCopy];
    if (contact == nil) {
        contact = [[CNMutableContact alloc] init];
        controller = [CNContactViewController viewControllerForNewContact:contact];
    } else {
        controller = [CNContactViewController viewControllerForNewContact:contact];
        UIBarButtonItem *leftButton = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain target:self action:@selector(tapLeftButton:)];
        controller.navigationItem.leftBarButtonItem = leftButton;
        controller.title = @"Edit Contact";
    }
    [self updateRecord:contact withData:contactData];
    
    controller.delegate = self;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
        UINavigationController *viewController = (UINavigationController*)[[[[UIApplication sharedApplication] delegate] window] rootViewController];
        [viewController presentViewController:navigation animated:YES completion:nil];
        
        NSDictionary *contactDict = [self contactToDictionary:contact withThumbnails:false];
        
        callback(@[[NSNull null], contactDict]);
    });
    
}

- (void)tapLeftButton:(id)sender {
    UINavigationController *viewController = (UINavigationController*)[[[[UIApplication sharedApplication] delegate] window] rootViewController];
    [viewController dismissViewControllerAnimated:YES completion:nil];
}

//dismiss open contact page after done or cancel is clicked
- (void)contactViewController:(CNContactViewController *)viewController didCompleteWithContact:(CNContact *)contact {
    [viewController dismissViewControllerAnimated:YES completion:nil];
}

RCT_EXPORT_METHOD(updateContact:(NSDictionary *)contactData callback:(RCTResponseSenderBlock)callback)
{
    CNContactStore* contactStore = [self contactsStore:callback];
    if(!contactStore)
        return;
    
    NSError* contactError;
    NSString* recordID = [contactData valueForKey:@"recordID"];
    NSArray * keysToFetch =@[
                             CNContactEmailAddressesKey,
                             CNContactPhoneNumbersKey,
                             CNContactFamilyNameKey,
                             CNContactGivenNameKey,
                             CNContactMiddleNameKey,
                             CNContactPostalAddressesKey,
                             CNContactOrganizationNameKey,
                             CNContactJobTitleKey,
                             CNContactImageDataAvailableKey,
                             CNContactThumbnailImageDataKey,
                             CNContactImageDataKey,
                             CNContactBirthdayKey
                             ];
    
    @try {
        CNMutableContact* record = [[contactStore unifiedContactWithIdentifier:recordID keysToFetch:keysToFetch error:&contactError] mutableCopy];
        [self updateRecord:record withData:contactData];
        CNSaveRequest *request = [[CNSaveRequest alloc] init];
        [request updateContact:record];
        
        [contactStore executeSaveRequest:request error:nil];
        
        NSDictionary *contactDict = [self contactToDictionary:record withThumbnails:false];
        
        callback(@[[NSNull null], contactDict]);
    }
    @catch (NSException *exception) {
        callback(@[[exception description], [NSNull null]]);
    }
}

-(void) updateRecord:(CNMutableContact *)contact withData:(NSDictionary *)contactData
{
    NSString *givenName = [contactData valueForKey:@"givenName"];
    NSString *familyName = [contactData valueForKey:@"familyName"];
    NSString *middleName = [contactData valueForKey:@"middleName"];
    NSString *company = [contactData valueForKey:@"company"];
    NSString *jobTitle = [contactData valueForKey:@"jobTitle"];
    NSDictionary *birthday = [contactData valueForKey:@"birthday"];
    
    contact.givenName = givenName;
    contact.familyName = familyName;
    contact.middleName = middleName;
    contact.organizationName = company;
    contact.jobTitle = jobTitle;
    
    if (birthday) {
        NSDateComponents *components;
        if (contact.birthday != nil) {
            components = contact.birthday;
        } else {
            components = [[NSDateComponents alloc] init];
        }
        if (birthday[@"month"] && birthday[@"day"]) {
            if (birthday[@"year"]) {
                components.year = [birthday[@"year"] intValue];
            }
            //months are indexed to 0 in JavaScript so we add 1 when assigning the month to DateComponent
            components.month = [birthday[@"month"] intValue] + 1;
            components.day = [birthday[@"day"] intValue];
        }
        
        contact.birthday = components;
    }
    
    NSMutableArray *phoneNumbers = [[NSMutableArray alloc]init];
    
    for (id phoneData in [contactData valueForKey:@"phoneNumbers"]) {
        NSString *label = [phoneData valueForKey:@"label"];
        NSString *number = [phoneData valueForKey:@"number"];
        
        CNLabeledValue *phone;
        if ([label isEqual: @"main"]){
            phone = [[CNLabeledValue alloc] initWithLabel:CNLabelPhoneNumberMain value:[[CNPhoneNumber alloc] initWithStringValue:number]];
        }
        else if ([label isEqual: @"mobile"]){
            phone = [[CNLabeledValue alloc] initWithLabel:CNLabelPhoneNumberMobile value:[[CNPhoneNumber alloc] initWithStringValue:number]];
        }
        else if ([label isEqual: @"iPhone"]){
            phone = [[CNLabeledValue alloc] initWithLabel:CNLabelPhoneNumberiPhone value:[[CNPhoneNumber alloc] initWithStringValue:number]];
        }
        else{
            phone = [[CNLabeledValue alloc] initWithLabel:label value:[[CNPhoneNumber alloc] initWithStringValue:number]];
        }
        
        [phoneNumbers addObject:phone];
    }
    contact.phoneNumbers = phoneNumbers;
    
    NSMutableArray *emails = [[NSMutableArray alloc]init];
    
    for (id emailData in [contactData valueForKey:@"emailAddresses"]) {
        NSString *label = [emailData valueForKey:@"label"];
        NSString *email = [emailData valueForKey:@"email"];
        
        if(label && email) {
            [emails addObject:[[CNLabeledValue alloc] initWithLabel:label value:email]];
        }
    }
    
    contact.emailAddresses = emails;
    
    NSMutableArray *postalAddresses = [[NSMutableArray alloc]init];
    
    for (id addressData in [contactData valueForKey:@"postalAddresses"]) {
        NSString *label = [addressData valueForKey:@"label"];
        NSString *street = [addressData valueForKey:@"street"];
        NSString *postalCode = [addressData valueForKey:@"postCode"];
        NSString *city = [addressData valueForKey:@"city"];
        NSString *country = [addressData valueForKey:@"country"];
        NSString *state = [addressData valueForKey:@"state"];
        
        if(label && street) {
            CNMutablePostalAddress *postalAddr = [[CNMutablePostalAddress alloc] init];
            postalAddr.street = street;
            postalAddr.postalCode = postalCode;
            postalAddr.city = city;
            postalAddr.country = country;
            postalAddr.state = state;
            [postalAddresses addObject:[[CNLabeledValue alloc] initWithLabel:label value: postalAddr]];
        }
    }
    
    contact.postalAddresses = postalAddresses;
    
    NSString *thumbnailPath = [contactData valueForKey:@"thumbnailPath"];
    
    if(thumbnailPath && [thumbnailPath rangeOfString:@"rncontacts_"].location == NSNotFound) {
        contact.imageData = [RCTContacts imageData:thumbnailPath];
    }
}

+ (NSData*) imageData:(NSString*)sourceUri
{
    if([sourceUri hasPrefix:@"assets-library"]){
        return [RCTContacts loadImageAsset:[NSURL URLWithString:sourceUri]];
    } else if ([sourceUri isAbsolutePath]) {
        return [NSData dataWithContentsOfFile:sourceUri];
    } else {
        return [NSData dataWithContentsOfURL:[NSURL URLWithString:sourceUri]];
    }
}

enum { WDASSETURL_PENDINGREADS = 1, WDASSETURL_ALLFINISHED = 0};

+ (NSData*) loadImageAsset:(NSURL*)assetURL {
    //thanks to http://www.codercowboy.com/code-synchronous-alassetlibrary-asset-existence-check/
    
    __block NSData *data = nil;
    __block NSConditionLock * albumReadLock = [[NSConditionLock alloc] initWithCondition:WDASSETURL_PENDINGREADS];
    //this *MUST* execute on a background thread, ALAssetLibrary tries to use the main thread and will hang if you're on the main thread.
    dispatch_async( dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        ALAssetsLibrary * assetLibrary = [[ALAssetsLibrary alloc] init];
        [assetLibrary assetForURL:assetURL
                      resultBlock:^(ALAsset *asset) {
                          ALAssetRepresentation *rep = [asset defaultRepresentation];
                          
                          Byte *buffer = (Byte*)malloc(rep.size);
                          NSUInteger buffered = [rep getBytes:buffer fromOffset:0.0 length:rep.size error:nil];
                          data = [NSData dataWithBytesNoCopy:buffer length:buffered freeWhenDone:YES];
                          
                          [albumReadLock lock];
                          [albumReadLock unlockWithCondition:WDASSETURL_ALLFINISHED];
                      } failureBlock:^(NSError *error) {
                          NSLog(@"asset error: %@", [error localizedDescription]);
                          
                          [albumReadLock lock];
                          [albumReadLock unlockWithCondition:WDASSETURL_ALLFINISHED];
                      }];
    });
    
    [albumReadLock lockWhenCondition:WDASSETURL_ALLFINISHED];
    [albumReadLock unlock];
    
    NSLog(@"asset lookup finished: %@ %@", [assetURL absoluteString], (data ? @"exists" : @"does not exist"));
    
    return data;
}

RCT_EXPORT_METHOD(deleteContact:(NSDictionary *)contactData callback:(RCTResponseSenderBlock)callback)
{
    if(!contactStore) {
        contactStore = [[CNContactStore alloc] init];
    }
    
    NSString* recordID = [contactData valueForKey:@"recordID"];
    
    NSArray *keys = @[CNContactIdentifierKey];
    
    
    @try {
        
        CNMutableContact *contact = [[contactStore unifiedContactWithIdentifier:recordID keysToFetch:keys error:nil] mutableCopy];
        NSError *error;
        CNSaveRequest *saveRequest = [[CNSaveRequest alloc] init];
        [saveRequest deleteContact:contact];
        [contactStore executeSaveRequest:saveRequest error:&error];
        
        callback(@[[NSNull null], recordID]);
    }
    @catch (NSException *exception) {
        callback(@[[exception description], [NSNull null]]);
    }
}

-(CNContactStore*) contactsStore: (RCTResponseSenderBlock)callback {
    if(!contactStore) {
        CNContactStore* store = [[CNContactStore alloc] init];
        
        if(!store.defaultContainerIdentifier) {
            NSLog(@"warn - no contact store container id");
            
            CNAuthorizationStatus authStatus = [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts];
            if (authStatus == CNAuthorizationStatusDenied || authStatus == CNAuthorizationStatusRestricted){
                callback(@[@"denied", [NSNull null]]);
            } else {
                callback(@[@"undefined", [NSNull null]]);
            }
            
            return nil;
        }
        
        contactStore = store;
    }
    
    return contactStore;
}

+ (BOOL)requiresMainQueueSetup
{
    return YES;
}


RCT_REMAP_METHOD(pickContact,
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject) {
    self.resolve = resolve;
    self.reject = reject;
    CNContactStore * contactStore = [[CNContactStore alloc] init];
    CNAuthorizationStatus status = [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts];
    switch (status) {
        case CNAuthorizationStatusNotDetermined: {
            [contactStore requestAccessForEntityType:CNEntityTypeContacts completionHandler:^(BOOL granted, NSError * __nullable error) {
                if (granted==YES) {
                    [self presentContactPicker];
                }
                else {
                    self.reject(@"access_denied", @"We need access to your contacts to use this feature, please go into your settings and enable it.", error);
                }
            }];
        }
            break;
        case CNAuthorizationStatusAuthorized:
            [self presentContactPicker];
            break;
        default:
            self.reject(@"access_denied", @"We need access to your contacts to use this feature, please go into your settings and enable it.", nil);
            break;
    }
}

// MARK: - ABAddress
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

-(void) getAllContacts:(RCTResponseSenderBlock)callback batchSize: (NSUInteger)size filter:(BOOL (^)(APContact *))filterBlock
{
    [self getAllAPContacts:^(NSArray<APContact *> *contacts) {
        NSMutableArray *contactDicts = [[NSMutableArray alloc] init];
        [contacts enumerateObjectsUsingBlock:^(APContact * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary *contactDictionary = [self apContactToDictionary:obj retainPhoneAndAddressLabel: NO];
            [contactDicts addObject:contactDictionary];
        }];
        callback(@[[NSNull null], contactDicts]);
    } batchSize:size filter:filterBlock];
}

-(void) getAllAPContacts:(void(^)(NSArray<APContact*>*contacts))callback batchSize: (NSUInteger)size filter:(BOOL (^)(APContact *contact))filterBlock {
    APAddressBook *addressBook = [[APAddressBook alloc] init];
    
    addressBook.sortDescriptors = @[
                                    [NSSortDescriptor sortDescriptorWithKey:@"recordDate.modificationDate" ascending:YES]
                                    ];
    
    addressBook.filterBlock = filterBlock;
    
    [addressBook setFieldsMask: (APContactFieldName | APContactFieldPhonesOnly | APContactFieldThumbnail | APContactFieldRecordDate)];
    [addressBook loadContacts:^(NSArray<APContact *> * _Nullable contacts, NSError * _Nullable error) {
        if (size > 0) {
            NSInteger count = MIN(contacts.count, size);
            NSArray *batchContacts = [contacts subarrayWithRange:NSMakeRange(0, count)];
            callback(batchContacts);
        } else {
            callback(contacts);
        }
    }];
}

-(NSDictionary*) apContactToDictionary:(APContact *) person retainPhoneAndAddressLabel:(BOOL) retainLabel
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
    
    if (!retainLabel) {
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
    [output setObject: [self apGetFilePathForThumbnailImage:person recordID:recordID] forKey:@"thumbnailPath"];
    
    return output;
}

-(NSString *) apGetFilePathForThumbnailImage:(APContact*) contact recordID:(NSString*) recordID
{
    NSString *filepath = [self thumbnailFilePath:recordID];
    
    if (contact.thumbnail){
        NSData *contactImageData = UIImagePNGRepresentation(contact.thumbnail);
        if (contactImageData) {
            BOOL success = [[NSFileManager defaultManager] createFileAtPath:filepath contents:contactImageData attributes:nil];
            
            if (!success) {
                NSLog(@"Unable to copy image");
                return @"";
            }
            
            return filepath;
        }
    }
    
    return @"";
}

- (NSString *)fullNameOfContact:(CNContact *)contact {
    NSString *givenName = contact.givenName;
    NSString *familyName = contact.familyName;
    NSString *middleName = contact.middleName;
    NSMutableArray *array = [NSMutableArray array];
    if (givenName.length > 0) {
        [array addObject:givenName];
    }
    if (middleName.length > 0) {
        [array addObject:middleName];
    }
    if (familyName.length > 0) {
        [array addObject:familyName];
    }
    return [[array componentsJoinedByString:@" "] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}


- (UIViewController *)rootViewController {
    UIViewController *vc = [[[[UIApplication sharedApplication] delegate] window] rootViewController];
    while (vc.presentedViewController != nil) {
        vc = vc.presentedViewController;
    }
    return vc;
}


- (void)presentContactPicker {
    CNContactPickerViewController *pickerController = [[CNContactPickerViewController alloc] init];
    pickerController.displayedPropertyKeys = @[CNContactPhoneNumbersKey];
    pickerController.delegate = self;
    [[self rootViewController] presentViewController:pickerController animated:true completion:nil];
}

// MARK: - CNContactPickerDelegate
- (void)contactPicker:(CNContactPickerViewController *)picker didSelectContacts:(NSArray<CNContact*> *)contacts {
    NSMutableArray *list = [NSMutableArray array];
    for (CNContact *contact in contacts) {
        NSString *name = [self fullNameOfContact:contact];
        for (CNLabeledValue<CNPhoneNumber *> *phone in contact.phoneNumbers) {
            NSString* value = [phone.value stringValue];
            if (value) {
                [list addObject:@{@"name": name, @"phone": value}];
            }
        }
        
    }
    if (self.resolve) {
        self.resolve(list);
    }
}
@end
