//
//  SessionController.m
//  Recon
//
//  Created by Sumanth Peddamatham on 7/1/09.
//  Copyright 2009 bafoontecha.com. All rights reserved.
//

#import "SessionController.h"
#import "ArgumentListGenerator.h"
#import "NmapController.h"
#import "XMLController.h"
#import "PrefsController.h"

#import "NSManagedObjectContext-helper.h"

#import <Foundation/NSFileManager.h>

// Managed Objects
#import "Session.h"
#import "Profile.h"


@interface SessionController ()

   //@property (readwrite, retain) Session *session; 
   @property (readwrite, retain) NSString *sessionUUID;   
   @property (readwrite, retain) NSString *sessionDirectory;
   @property (readwrite, retain) NSString *sessionOutputFile;   

   @property (readwrite, assign) BOOL hasRun;   
   @property (readwrite, assign) BOOL isRunning;
   @property (readwrite, assign) BOOL deleteAfterAbort;

   @property (readwrite, retain) NSArray *nmapArguments;   
   @property (readwrite, assign) NmapController *nmapController;

   @property (readwrite, retain) NSTimer *resultsTimer;
   @property (readwrite, assign) XMLController *xmlController;

@end


@implementation SessionController

@synthesize session;
@synthesize sessionUUID;
@synthesize sessionDirectory;
@synthesize sessionOutputFile;

@synthesize hasRun;
@synthesize isRunning;
@synthesize deleteAfterAbort;

@synthesize nmapArguments;
@synthesize nmapController;

@synthesize resultsTimer;
@synthesize xmlController;

- (id)init
{
   if (![super init])
      return nil;
   
   // Generate a unique identifier for this controller
   self.sessionUUID = [SessionController stringWithUUID];
      
   self.hasRun = FALSE;
   self.isRunning = FALSE;
   self.deleteAfterAbort = FALSE;   
   
   self.xmlController = [[XMLController alloc] init];
   return self;
}

- (void)dealloc
{
   //ANSLog(@"");
   //NSLog(@"SessionController: deallocating");      
   
   NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
   [nc removeObserver:self];

   [session release];
   [sessionUUID release];   
   [sessionDirectory release];   
   [sessionOutputFile release];
   
   [nmapArguments release];       
   [nmapController release];

   [resultsTimer invalidate];   
   [resultsTimer release];
   [xmlController release];
   [super dealloc];
}

#pragma mark -

// -------------------------------------------------------------------------------
//	initWithProfile
// -------------------------------------------------------------------------------
- (Session *)initWithProfile:(Profile *)profile                           
            withTarget:(NSString *)sessionTarget               
inManagedObjectContext:(NSManagedObjectContext *)context
{
//   NSLog(@"SessionController: initWithProfile!");
   
   // Make a copy of the selected profile
   Profile *profileCopy = [self copyProfile:profile];
   
   // Create new session in managedObjectContext
   session = [NSEntityDescription insertNewObjectForEntityForName:@"Session" 
                                                    inManagedObjectContext:context];   
   [session setTarget:sessionTarget];     // Store session target
   [session setDate:[NSDate date]];       // Store session start date
   [session setUUID:[self sessionUUID]];  // Store session UUID
   [session setStatus:@"Queued"];         // Store session status
   [session setProfile:profileCopy];      // Store session profile
   
         
   [self createSessionDirectory:sessionUUID];
         
   ArgumentListGenerator *a = [[ArgumentListGenerator alloc] init];

   // Convert selected profile to nmap arguments
   self.nmapArguments = [a convertProfileToArgs:profile withTarget:sessionTarget withOutputFile:sessionOutputFile];   

   [self initNmapController];   
   
   [a release];

   return session;
}

// -------------------------------------------------------------------------------
//	initWithSession: 
// -------------------------------------------------------------------------------
- (Session *)initWithSession:(Session *)existingSession
{
   Profile *profile = [existingSession profile];
   
   self.session = existingSession;
   self.sessionUUID = [existingSession UUID];

   [self createSessionDirectory:[existingSession UUID]];

   // Convert selected profile to nmap arguments   
   ArgumentListGenerator *a = [[ArgumentListGenerator alloc] init];
   self.nmapArguments = [a convertProfileToArgs:profile withTarget:[existingSession target] withOutputFile:sessionOutputFile];   

   [self initNmapController];   
   
   [a release];
   
   return session;  
}

// -------------------------------------------------------------------------------
//	copyProfile: Return a copy of the profile, filed under the hidden "Saved Sessions" folder
// -------------------------------------------------------------------------------
- (Profile *)copyProfile:(Profile *)profile
{   
   NSArray *array = [[profile managedObjectContext] fetchObjectsForEntityName:@"Profile" 
                                                             withPredicate:@"name == '_Saved Sessions'"];
   
   // Saved Sessions Folder
   Profile *savedSessions = [array lastObject];
   
   // Make a copy of the selected profile
   Profile *profileCopy = [NSEntityDescription insertNewObjectForEntityForName:@"Profile" 
                                                         inManagedObjectContext:[profile managedObjectContext]];
   NSDictionary *values = [profile dictionaryWithValuesForKeys:[[profileCopy entity] attributeKeys]];      
   [profileCopy setValuesForKeysWithDictionary:values];      
   [profileCopy setName:[NSString stringWithFormat:@"Copy of %@",[profile name]]];
   [profileCopy setIsEnabled:NO];   
   [profileCopy setParent:savedSessions];
   
   return profileCopy;
}

// -------------------------------------------------------------------------------
//	createSessionDirectory: 
// -------------------------------------------------------------------------------
- (BOOL)createSessionDirectory:(NSString *)uuid
{
   PrefsController *prefs = [PrefsController sharedPrefsController];
   
   // Create directory for new session   
   NSFileManager *NSFm = [NSFileManager defaultManager];
   self.sessionDirectory = [[prefs reconSessionFolder] stringByAppendingPathComponent:uuid];
   self.sessionOutputFile = [sessionDirectory stringByAppendingPathComponent:@"nmap-output.xml"];
   
   if ([NSFm createDirectoryAtPath:sessionDirectory attributes: nil] == NO) {
      //ANSLog (@"Couldn't create directory!\n");
      // TODO: Notify SessionManager of file creation error
      return NO;
   }
   
   return YES;
}

// -------------------------------------------------------------------------------
//	initNmapController: Initialize an Nmap Controller for this Session Controller
// -------------------------------------------------------------------------------
- (void)initNmapController
{
   PrefsController *prefs = [PrefsController sharedPrefsController];
   
   // Call NmapController with outputFile and argument list   
   self.nmapController = [[NmapController alloc] initWithNmapBinary:[prefs nmapBinary]                                                   
                                                           withArgs:nmapArguments 
                                                 withOutputFilePath:sessionDirectory];   

   // Register to receive notifications from the initialized NmapController
   NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
   [nc addObserver:self
          selector:@selector(successfulRunNotification:)
              name:@"NCsuccessfulRun"
            object:nmapController];
   [nc addObserver:self
          selector:@selector(abortedRunNotification:)
              name:@"NCabortedRun"
            object:nmapController];
   [nc addObserver:self
          selector:@selector(unsuccessfulRunNotification:)
              name:@"NCunsuccessfulRun"
            object:nmapController];
   
   //ANSLog(@"SessionController: Registered with notification center");      
}

// -------------------------------------------------------------------------------
//	startScan
// -------------------------------------------------------------------------------
- (void)startScan
{      
   // Reinitialize controller if previously run/aborted
   if ([nmapController hasRun])
      [self initNmapController];
   
   self.hasRun = TRUE;   
   self.isRunning = TRUE;
   [session setStatus:@"Running"];
   
   // Setup a timer to read the progress
   resultsTimer = [[NSTimer scheduledTimerWithTimeInterval:0.8
                                             target:self
                                           selector:@selector(readProgress:)
                                           userInfo:nil
                                            repeats:YES] retain];   
   
   [nmapController startScan];

//   // DEBUGGING!
//   //[xmlController parseXMLFile:sessionOutputFile inSession:session];
//   [self successfulRunNotification:nil];
}

// -------------------------------------------------------------------------------
//	readProgress: Called by the resultsTimer.  Parses nmap-output.xml for 'taskprogress'
//               to update the status bar in the Sessions Drawer.
// -------------------------------------------------------------------------------
- (void)readProgress:(NSTimer *)aTimer
{
   @synchronized(lock)
   {
      NSTask *task = [[NSTask alloc] init];
      [task setLaunchPath:@"/bin/tcsh"];     // For some reason, using /bin/sh screws up the debug console   
      NSString *p = [NSString stringWithFormat:@"cat '%@' | grep taskprogress | tail -1 | awk -F '\"' '{print $2 \",\" $6}'", sessionOutputFile];
      [task setArguments:[NSArray arrayWithObjects: @"-c", p, nil]];
      
      // Create the pipe to read from
      NSPipe *outPipe = [[NSPipe alloc] init];
      [task setStandardOutput:outPipe];
      [outPipe release];
      
      // Start the process
      [task launch];
      
      // Read the output
      NSData *data = [[outPipe fileHandleForReading]
                      readDataToEndOfFile];
      
      // Make sure the task terminates normally
      [task waitUntilExit];
      [task release];
      
      // Convert to a string
      NSString *aString = [[NSString alloc] initWithData:data
                                                encoding:NSUTF8StringEncoding];
      
      NSArray *a = [aString componentsSeparatedByString:@","];
      
      if ([a count] == 2)
      {
         NSString *a1 = [a objectAtIndex:0];
         NSString *a2 = [a objectAtIndex:1];
         
         if ((a1 != nil) && (a2 != nil))
         {
            // If notifications have already hit, no need to update status
            if ( ([[session status] isEqualToString:@"Done"]) ||
                 ([[session status] isEqualToString:@"Aborted"])
               )
            {
               return;
            }
            else
            {   
               [session setStatus:[a objectAtIndex:0]];
               [session setProgress:[NSNumber numberWithFloat:[[a objectAtIndex:1] floatValue]]];
            }
         }
      }
      
      [aString release];
   }
}

// -------------------------------------------------------------------------------
//	abortScan
// -------------------------------------------------------------------------------
- (void)abortScan
{
   //ANSLog(@"Received abort for %@", sessionUUID);
   self.hasRun = TRUE;
   [nmapController abortScan];  
}

// -------------------------------------------------------------------------------
//	deleteSession: Remove the current session from Core Data.  Works even if the
//                session is currently running.
// -------------------------------------------------------------------------------
- (void)deleteSession
{
   self.hasRun = TRUE;
   self.deleteAfterAbort = TRUE;   
   [nmapController abortScan];
}

#pragma mark -
#pragma mark Notification center handlers

// -------------------------------------------------------------------------------
//	successfulRunNotification: NmapController notifies us that the NTask has completed.
// -------------------------------------------------------------------------------
- (void)successfulRunNotification: (NSNotification *)notification
{    
   @synchronized(lock)
   {      
      // Invalidate the progess timer
      [resultsTimer invalidate];
      
      // Call XMLController with session directory and managedObjectContext
      [session setStatus:@"Parsing output"];
      [xmlController parseXMLFile:sessionOutputFile inSession:session];      

      self.isRunning = FALSE;
      [session setStatus:@"Done"];
      [session setProgress:[NSNumber numberWithFloat:100]];   

      // Set up "Console" pointers
      NSString *nmapOutputStdout = [sessionOutputFile stringByReplacingOccurrencesOfString:@"nmap-output.xml" 
                                                                                withString:@"nmap-stdout.txt"];
      NSString *nmapOutputStderr = [sessionOutputFile stringByReplacingOccurrencesOfString:@"nmap-output.xml" 
                                                                                withString:@"nmap-stderr.txt"];

      [session setNmapOutputXml:sessionOutputFile];
      [session setNmapOutputStdout:nmapOutputStdout];
      [session setNmapOutputStderr:nmapOutputStderr];
      
      // Send notification to SessionManager that session is complete
      NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
      [nc postNotificationName:@"SCsuccessfulRun" object:self];
   }
}

// -------------------------------------------------------------------------------
//	abortedRunNotification: 
// -------------------------------------------------------------------------------
- (void)abortedRunNotification: (NSNotification *)notification
{
   @synchronized(lock)
   {       
      // Invalidate the progess timer
      [resultsTimer invalidate];   

      self.isRunning = FALSE;
      [session setStatus:@"Aborted"];
      [session setProgress:[NSNumber numberWithFloat:0]];

      if (deleteAfterAbort == TRUE)
      {            
         NSManagedObjectContext *context = [session managedObjectContext];
         [context deleteObject:session];
      }   
      
      // Send notification to SessionManager that session is complete
      NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
      [nc postNotificationName:@"SCabortedRun" object:self];         
   }         
}

// -------------------------------------------------------------------------------
//	unsuccessfulRunNotification: 
// -------------------------------------------------------------------------------
- (void)unsuccessfulRunNotification:(NSNotification *)notification
{
   @synchronized(lock)
   {
      // Invalidate the progess timer
      [resultsTimer invalidate];   
      
      self.isRunning = FALSE;
      [session setStatus:@"Error"];   
      [session setProgress:[NSNumber numberWithFloat:0]];   
      
      // Set up "Console" pointers
      NSString *nmapOutputStdout = [sessionOutputFile stringByReplacingOccurrencesOfString:@"nmap-output.xml" 
                                                                                withString:@"nmap-stdout.txt"];
      NSString *nmapOutputStderr = [sessionOutputFile stringByReplacingOccurrencesOfString:@"nmap-output.xml" 
                                                                                withString:@"nmap-stderr.txt"];
      
      [session setNmapOutputXml:sessionOutputFile];
      [session setNmapOutputStdout:nmapOutputStdout];
      [session setNmapOutputStderr:nmapOutputStderr];   
      
      // Send notification to SessionManager that session is complete
      NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
      [nc postNotificationName:@"SCunsuccessfulRun" object:self]; 
   }
}   

// -------------------------------------------------------------------------------
//	stringWithUUID: Returns a unique identifier for Session.  
//                 This helps avoid conflicts when creating session directories.
// -------------------------------------------------------------------------------
+ (NSString *)stringWithUUID 
{
   CFUUIDRef uuidObj = CFUUIDCreate(nil);
   NSString *uuidString = (NSString*)CFUUIDCreateString(nil, uuidObj);
   CFRelease(uuidObj);
   return [uuidString autorelease];
}

@end
