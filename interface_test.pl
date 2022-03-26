#!/usr/bin/perl
# standard modules
use strict;
use warnings;

# load wxPerl main module
use Wx;

# every application must create an application object

package MyApp;
use base 'Wx::App';

# The OnInit method is called automatically when an
# application object is first constructed.
# Application level initialization can be done here.

sub OnInit {
    my( $self ) = @_;
    # create a new frame (a frame is a top level window)
    my $frame = Wx::Frame->new(
        undef,           # parent window
        -1,              # ID -1 means any
        'Hello World',   # title
        [-1, -1],        # default position
        [250, 150],      # size
    );

    # show the frame
    $frame->Show( 1 );
    
    # The OnInit sub must return a true value or the wxApp
    # will not start. Although an explicit return is not
    # necessary as the $frame->Show line will return
    # a true value, we'll include an explicit line
    # in this example.
    
    return 1;
}

package main;

# create the application object, this will call OnInit
# before the constructor returns.

my $app = MyApp->new;

# process GUI events from the application this function
# will not return until the last frame is closed

$app->MainLoop;
