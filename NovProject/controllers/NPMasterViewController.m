//
//  NPMasterViewController.m
//  NPBoston
//
//  Created by Tony DiPasquale on 4/17/13.
//  Copyright (c) 2013 Tony DiPasquale. All rights reserved.
//

#import <MapKit/MapKit.h>
#import <QuartzCore/QuartzCore.h>

#import "NPMasterViewController.h"
#import "NPResultsViewController.h"
#import "NPVerbalViewController.h"
#import "NPMapViewController.h"
#import "NPAPIClient.h"
#import "SVProgressHUD.h"
#import "NPWorkout.h"
#import "WCAlertView.h"
#import "NPUtils.h"
#import "NPUser.h"
#import "LUKeychainAccess.h"

@interface NPMasterViewController ()

@property (strong, nonatomic) NSMutableArray *workouts;
@property (strong, nonatomic) NPUser *user;
@property (strong, nonatomic) NPWorkout *selectedWorkout;
@property (strong, nonatomic) NSIndexPath *selectedIndexPath;
@property (strong, nonatomic) NSDateFormatter *dateFormatter;

@end

@implementation NPMasterViewController

#pragma mark - View flow

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    if (![[LUKeychainAccess standardKeychainAccess] objectForKey:@"user"]) {
        [self performSegueWithIdentifier:@"LoginViewSegue" sender:self];
    } else {
        self.user = (NPUser *)[NSKeyedUnarchiver unarchiveObjectWithData:[[LUKeychainAccess standardKeychainAccess] objectForKey:@"user"]];
    }
    
    [[Mixpanel sharedInstance] track:@"master view loaded"];
    
    [[Mixpanel sharedInstance] track:@"workout types request attempted"];
    [[NPAPIClient sharedClient] getPath:@"workout_types" parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSArray *types = [responseObject objectForKey:@"data"];
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:types forKey:@"types"];
        [defaults synchronize];
        [[Mixpanel sharedInstance] track:@"workout types request succeeded"];
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        [NPUtils reportError:error WithMessage:@"workout types request failed" FromOperation:(AFJSONRequestOperation *)operation];
    }];
    
    self.dateFormatter = [[NSDateFormatter alloc] init];
    [self.dateFormatter setDateFormat:@"E - MMM dd, yyyy - hh:mma"];
    [self.dateFormatter setTimeZone:[NSTimeZone localTimeZone]];
    
    self.workouts = [[NSMutableArray alloc] init];
    
    if (self.user) {
        [self getWorkouts];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [self becomeFirstResponder];
    [super viewWillAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [self resignFirstResponder];
    [super viewWillDisappear:animated];
}

#pragma mark - NPLoginViewController Delegate

- (void)userLoggedIn:(NPUser *)u
{
    self.user = u;
    [[LUKeychainAccess standardKeychainAccess] setObject:[NSKeyedArchiver archivedDataWithRootObject:self.user] forKey:@"user"];
    
    [[Mixpanel sharedInstance] identify:self.user.objectId];
    [[[Mixpanel sharedInstance] people] set:@"$name" to:self.user.name];
    [[[Mixpanel sharedInstance] people] set:@"$gender" to:self.user.gender];
    
    [self getWorkouts];
}

#pragma mark - Populate data

- (void)getWorkouts
{
    [[Mixpanel sharedInstance] track:@"workouts request attempted"];
    [SVProgressHUD showWithStatus:@"Loading..."];
    [[NPAPIClient sharedClient] getPath:@"workouts" parameters:@{@"location": self.user.location} success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSArray *data = [responseObject valueForKey:@"data"];
        
        [self.workouts removeAllObjects];
        
        for (id object in data) {
            [self.workouts addObject:[NPWorkout workoutWithObject:object]];
        }
        
        [self.tableView reloadData];
        [SVProgressHUD dismiss];
        [[Mixpanel sharedInstance] track:@"workouts request succeeded"];
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {        
        NSString *msg = [NPUtils reportError:error WithMessage:@"workouts request failed" FromOperation:(AFJSONRequestOperation *)operation];
        
        [SVProgressHUD dismiss];        
        [[[UIAlertView alloc] initWithTitle:@"Error Occured" message:msg delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    }];
}

#pragma mark - Handle shake

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event
{
    if (event.subtype == UIEventSubtypeMotionShake) {
        [WCAlertView showAlertWithTitle:@"Go Back?" message:@"Would you like to go back to the simpler version?" customizationBlock:nil completionBlock:^(NSUInteger buttonIndex, WCAlertView *alertView) {
            if (buttonIndex == 0) {
                NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                [defaults setBool:NO forKey:@"unlocked"];
                [defaults synchronize];
                
                [[[UIAlertView alloc] initWithTitle:@"Restart the App!" message:@"Exit the app then double click the home button.  Hold down the app icon and click the red circle." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
            }
        } cancelButtonTitle:@"No" otherButtonTitles:@"Yes", nil];
    }
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.workouts.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NPWorkoutCell *cell = [tableView dequeueReusableCellWithIdentifier:@"WorkoutCell"];
    
    if (!cell.delegate) {
        cell.delegate = self;
    }
    
    NPWorkout *workout = self.workouts[indexPath.row];
    [cell.titleLabel setText:workout.title];
    [cell.subtitleLabel setText:[self.dateFormatter stringFromDate:workout.date]];
    
    if ([workout.details stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0) {
        [cell.detailsLabel setHidden:YES];
        
        [cell.cellView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(6)-[titleLabel]-(2)-[subtitleLabel]-(210)-(<=6)-[viewVerbalsButton][actionsView(==44)]|" options:0 metrics:nil views:@{@"titleLabel": cell.titleLabel, @"subtitleLabel": cell.subtitleLabel, @"actionsView": cell.actionsView, @"viewVerbalsButton": cell.viewVerbalsButton}]];
    } else {
        [cell.detailsLabel setHidden:NO];
        [cell.detailsLabel setText:workout.details];
        
        int h = [workout.details sizeWithFont:[UIFont systemFontOfSize:15] constrainedToSize:CGSizeMake(240, 999) lineBreakMode:NSLineBreakByWordWrapping].height;
        
        [cell.cellView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:[NSString stringWithFormat:@"V:|-(6)-[titleLabel]-(2)-[subtitleLabel]-(210)-[detailsLabel(==%d)]-(<=6)-[viewVerbalsButton][actionsView(==44)]|", h] options:0 metrics:nil views:@{@"titleLabel": cell.titleLabel, @"subtitleLabel": cell.subtitleLabel, @"detailsLabel": cell.detailsLabel, @"actionsView": cell.actionsView, @"viewVerbalsButton": cell.viewVerbalsButton}]];
    }
    
    [cell.actionsView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[verbalButton(==44)]|" options:0 metrics:nil views:@{@"verbalButton": cell.verbalButton}]];
    
    CLLocationCoordinate2D coor;
    MKCoordinateRegion region;
    MKCoordinateSpan span;
    
    if (workout.lat) {
        coor.latitude = [workout.lat doubleValue];
        coor.longitude = [workout.lng doubleValue];
        
        MKPointAnnotation *point = [[MKPointAnnotation alloc] init];
        [point setCoordinate:coor];
        [cell.locationMap addAnnotation:point];
        
        span.latitudeDelta = .02;
        span.longitudeDelta = .02;
    } else {
        coor.latitude = 42.358431;
        coor.longitude = -71.059773;
        span.latitudeDelta = .01;
        span.longitudeDelta = .01;
    }
    
    region.center = coor;
    region.span = span;
    [cell.locationMap setRegion:region];
    cell.locationMap.scrollEnabled = NO;
    cell.locationMap.zoomEnabled = NO;
    
    [cell.viewVerbalsButton setTitle:[NSString stringWithFormat:@"(%d) Verbals", [workout.verbalsCount integerValue]] forState:UIControlStateNormal];
    [cell.viewResultsButton setTitle:[NSString stringWithFormat:@"(%d) Results", [workout.resultsCount integerValue]] forState:UIControlStateNormal];
    
    [cell.verbalButton setTitleColor:[UIColor grayColor] forState:UIControlStateNormal];
    [cell.resultsButton setTitleColor:[UIColor grayColor] forState:UIControlStateNormal];
    
    if (workout.verbal) {
        [cell.verbalButton setTitleColor:[UIColor colorWithRed:(28/255.0) green:(164/255.0) blue:(190/255.0) alpha:1] forState:UIControlStateNormal];
    }
    
    if (workout.result) {
        [cell.resultsButton setTitleColor:[UIColor colorWithRed:(28/255.0) green:(164/255.0) blue:(190/255.0) alpha:1] forState:UIControlStateNormal];
    }

    cell.workout = workout;
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NPWorkout *workout = self.workouts[indexPath.row];
    
    if ([workout.details stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0) return 387;
    
    return [workout.details sizeWithFont:[UIFont systemFontOfSize:15] constrainedToSize:CGSizeMake(240, 999) lineBreakMode:NSLineBreakByWordWrapping].height + 387;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the specified item to be editable.
    return NO;
}

#pragma mark - NPWorkoutCell Delegate

- (void)showMapWithWorkout:(NPWorkout *)workout
{
    self.selectedWorkout = workout;
    [self performSegueWithIdentifier:@"ViewMapSegue" sender:self];
}

- (void)showResultsWithWorkout:(NPWorkout *)workout
{
    self.selectedWorkout = workout;
    [self performSegueWithIdentifier:@"ViewResultsSegue" sender:self];
}

- (void)showVerbalsWithWorkout:(NPWorkout *)workout
{
    self.selectedWorkout = workout;
    [self performSegueWithIdentifier:@"ViewVerbalsSegue" sender:self];
}

- (void)submitResultsWithIndexPath:(NSIndexPath *)indexPath
{
    self.selectedWorkout = self.workouts[indexPath.row];
    self.selectedIndexPath = indexPath;
    [self performSegueWithIdentifier:@"SubmitResultsSegue" sender:self];
}

#pragma mark - NPResultsSubmit Delegate

- (void)resultsSaved
{
    [[(NPWorkoutCell *)[self.tableView cellForRowAtIndexPath:self.selectedIndexPath] resultsButton] setTitleColor:[UIColor colorWithRed:(28/255.0) green:(164/255.0) blue:(190/255.0) alpha:1] forState:UIControlStateNormal];
    
    [self getWorkouts];
}

#pragma mark - Overridden methods

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([[segue identifier] isEqualToString:@"SubmitResultsSegue"]) {
        NPSubmitResultsViewController *view = [segue destinationViewController];
        view.workout = self.selectedWorkout;
        view.delegate = self;
    } else if ([[segue identifier] isEqualToString:@"ViewResultsSegue"]) {
        NPResultsViewController *view = [segue destinationViewController];
        view.workout = self.selectedWorkout;
    } else if ([[segue identifier] isEqualToString:@"ViewVerbalsSegue"]) {
        NPVerbalViewController *view = [segue destinationViewController];
        view.workout = self.selectedWorkout;
    } else if ([[segue identifier] isEqualToString:@"ViewMapSegue"]) {
        NPMapViewController *view = [segue destinationViewController];
        view.workout = self.selectedWorkout;
    } else if ([[segue identifier] isEqualToString:@"LoginViewSegue"]) {
        NPLoginViewController *view = [segue destinationViewController];
        view.delegate = self;
    }
}
@end