# See bottom of file for default license and copyright information



# change the package name!!!
package Foswiki::Plugins::RedmineIntegrationPlugin;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Func    ();    # The plugins API
use Foswiki::Plugins ();    # For the API version

use DBI;
use Encode;
use JSON;
use Data::Dumper;
use DateTime;
use DateTime::Format::DBI;

my $db;
my $db_schema;

# $VERSION is referred to by Foswiki, and is the only global variable that
# *must* exist in this package.  Two version formats are supported:
#
# Recommended:  Simple decimal version.   Use "1.2" format for releases
# Do NOT use the "v" prefix.  This style is set either by using the "parse"
# method, or by a simple assignment.
#
#    our $VERSION = "1.20";
#
# If you intend to use the _nnn "alpha suffix, declare it using version->parse().
#
#    use version; our $VERSION = version->parse("1.20_001");
#
# Alternative:  Dotted triplet.  Use "v1.2.3" format for releases,  and
# "v1.2.3_001" for "alpha" versions.  The v prefix is required.
# This format uses the "declare" format These statements MUST be on the same
# line. See "perldoc version" for more information on version strings.
#
#     use version; our $VERSION = version->declare("v1.2.0");
#
# To convert from a decimal version to a dotted version, first normalize the
# decimal version, then increment it.
# perl -Mversion -e 'print version->parse("4.44")->normal'  ==>  v4.440.0
# In this example the next version would be v4.441.0.
#
# Note:  Alpha versions compare as numerically lower than the non-alpha version
# so the versions in ascending order are:
#   v1.2.1_001 -> v1.2.1 -> v1.2.2_001 -> v1.2.2
#
use version; our $VERSION = version->declare("v1.1.7");

# $RELEASE is used in the "Find More Extensions" automation in configure.
# It is a manually maintained string used to identify functionality steps.
# You can use any of the following formats:
# tuple   - a sequence of integers separated by . e.g. 1.2.3. The numbers
#           usually refer to major.minor.patch release or similar. You can
#           use as many numbers as you like e.g. '1' or '1.2.3.4.5'.
# isodate - a date in ISO8601 format e.g. 2009-08-07
# date    - a date in 1 Jun 2009 format. Three letter English month names only.
# Note: it's important that this string is exactly the same in the extension
# topic - if you use %$RELEASE% with BuildContrib this is done automatically.
# It is preferred to keep this compatible with $VERSION. At some future
# date, Foswiki will deprecate RELEASE and use the VERSION string.
#
our $RELEASE = "1.1";

# Short description of this plugin
# One line description, is shown in the %SYSTEMWEB%.TextFormattingRules topic:
our $SHORTDESCRIPTION = 'Empty Plugin used as a template for new Plugins';

# You must set $NO_PREFS_IN_TOPIC to 0 if you want your plugin to use
# preferences set in the plugin topic. This is required for compatibility
# with older plugins, but imposes a significant performance penalty, and
# is not recommended. Instead, leave $NO_PREFS_IN_TOPIC at 1 and use
# =$Foswiki::cfg= entries, or if you want the users
# to be able to change settings, then use standard Foswiki preferences that
# can be defined in your %USERSWEB%.SitePreferences and overridden at the web
# and topic level.
#
# %SYSTEMWEB%.DevelopingPlugins has details of how to define =$Foswiki::cfg=
# entries so they can be used with =configure=.
our $NO_PREFS_IN_TOPIC = 1;


sub initPlugin {
    my ( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if ( $Foswiki::Plugins::VERSION < 2.0 ) {
        Foswiki::Func::writeWarning( 'Version mismatch between ',
            __PACKAGE__, ' and Plugins.pm' );
        return 0;
    }

    Foswiki::Func::registerTagHandler( 'GET_ISSUE', \&_GET_ISSUE );
    Foswiki::Func::registerTagHandler( 'GET_ISSUE_URL', \&_GET_ISSUE_URL );

    Foswiki::Func::registerRESTHandler( 'search_issue', \&search_issue, http_allow=>'GET' );
    Foswiki::Func::registerRESTHandler( 'get_activitys', \&get_activitys, http_allow=>'GET' );
    Foswiki::Func::registerRESTHandler( 'add_time_entry', \&add_time_entry, http_allow=>'POST' );




    # Plugin correctly initialized
    return 1;
}


sub db {
    return $db if defined $db;

    my $host = $Foswiki::cfg{RedmineIntegrationPlugin}{Host} || "localhost";
    my $port = $Foswiki::cfg{RedmineIntegrationPlugin}{Port} || 5432;
    my $dbname = $Foswiki::cfg{RedmineIntegrationPlugin}{Name} || "";
    my $username = $Foswiki::cfg{RedmineIntegrationPlugin}{User} || "";
    my $password = $Foswiki::cfg{RedmineIntegrationPlugin}{Password} || "";

    $db_schema = $username;

    $db = DBI->connect("dbi:Pg:dbname=$dbname;host=$host;port=$port;", "$username", "$password" ,{
        RaiseError => 1,
        PrintError => 0,
        AutoCommit => 1,
        FetchHashKeyName => 'NAME_lc',
    });
    return $db;
}

sub css {
    return <<CSS;
    <style media="all" type="text/css" >
    \@import url("%PUBURLPATH%/%SYSTEMWEB%/RedmineIntegrationPlugin/rip.css?r=$RELEASE")
    </style>
CSS
}

sub _GET_ISSUE_URL {
  my($session, $params, $topic, $web, $topicObject) = @_;

  my $redmine_url = $Foswiki::cfg{RedmineIntegrationPlugin}{RedmineURL} || "";
  my $redmine_issue_url = "$redmine_url/issues/$params->{_DEFAULT}";

  return $redmine_issue_url;

}


sub _GET_ISSUE {
  my($session, $params, $topic, $web, $topicObject) = @_;

  my $db = db();

  my $sql = q/
    SELECT
      issues.id as id,
      issues.subject as subject,
      trackers.name as tracker,
      issue_statuses.name as status,
      users.firstname || ' ' || users.lastname as assigned_to
    FROM issues
    LEFT JOIN issue_statuses ON issues.status_id = issue_statuses.id
    LEFT JOIN users ON issues.assigned_to_id = users.id
    LEFT JOIN trackers ON issues.tracker_id = trackers.id
    WHERE issues.id = ?
    /;

  Foswiki::Func::addToZone('script', 'RedmineIntegrationPluginCSS', css);

  my $values_ref = $db->selectrow_hashref($sql, undef, $params->{_DEFAULT});

  my $redmine_logo_path = '%PUBURL%/%SYSTEMWEB%/RedmineIntegrationPlugin/redmine_fluid_icon.png';

  return "<div class='redmine_issue_link'><img alt='redmine_icon' src='$redmine_logo_path'> <a target='_blank' href='%GET_ISSUE_URL{$values_ref->{'id'}}%'>$values_ref->{'tracker'} #$values_ref->{'id'}</a>: $values_ref->{'status'} | $values_ref->{'subject'}</div>";

}


sub build_server_error_response {
  my ( $message, $response ) = @_;

  $response->header( -status => 500, -type => 'application/json', -charset => 'UTF-8' );
  $response->print( to_json({status => 'error', 'code' => 'server_error', msg => $message}));
  return;

}


sub search_issue {
  my ( $session, $subject, $verb, $response ) = @_;
  my $res;
  my $req;
  my $query = $session->{request};

  eval {

    my $db = db();

    $req = $query->param("q");

    my $sql = q/
    SELECT
      issues.id as issue_id,
      issues.project_id as project_id,
      issues.subject as subject,
      trackers.name as tracker,
      issue_statuses.name as status,
      users.firstname || ' ' || users.lastname as assigned_to
    FROM issues
    LEFT JOIN issue_statuses ON issues.status_id = issue_statuses.id
    LEFT JOIN users ON issues.assigned_to_id = users.id
    LEFT JOIN trackers ON issues.tracker_id = trackers.id
    WHERE issues.subject LIKE '%'||?||'%' OR issues.id = ?
    /;

    $res = db()->selectall_arrayref($sql, {Slice => {}}, $req, int($req));

  
  };
  if ($@) {
      $response->header( -status => 500, -type => 'application/json', -charset => 'UTF-8' );
      $response->print( to_json({status => 'error', 'code' => 'server_error', msg => "Server error: $@"}));
      return
  }

  $response->header( -status => 200, -type => 'application/json', -charset => 'UTF-8' );
  $response->print(return to_json($res));
  return

}

sub get_activitys {
  my ( $session, $subject, $verb, $response ) = @_;
  my $res;
  my $req;
  my $query = $session->{request};

  eval {

    my $sql = "select * from enumerations where type='TimeEntryActivity' and ((parent_id is null and id not in (select parent_id from enumerations where project_id=?)) or project_id=?) and active=true;";

    $res = db()->selectall_arrayref($sql, {Slice => {}}, $query->param("p"), $query->param("p"));

  
  };
  if ($@) {
      $response->header( -status => 500, -type => 'application/json', -charset => 'UTF-8' );
      $response->print( to_json({status => 'error', 'code' => 'server_error', msg => "Server error: $@"}));
      return
  }

  $response->header( -status => 200, -type => 'application/json', -charset => 'UTF-8' );
      $response->print( to_json($res));
      return

}



sub add_time_entry {
  my ( $session, $subject, $verb, $response ) = @_;

  my $res;
  my $req;
  my $q = $session->{request};
  my $rv;

  my $db = db();

  eval { $req = from_json($q->param("POSTDATA") || '{}') };
  if ($@) { return build_server_error_response("No JSON Data!", $response) };

  # Get User ID by loginname
  $req->{user_name} = lc($session->{user});
  my $sql_get_user_id = "SELECT id FROM users WHERE login = ?";
  $req->{user_id} = $db->selectrow_hashref($sql_get_user_id, undef, $req->{user_name})->{id};

  # Check if user exist in Redmine
  my $sql_check_user_id = "SELECT Count(*) FROM users WHERE id = ?";
  if ($db->selectrow_hashref($sql_check_user_id, undef, $req->{user_id})->{count} == 0) {
  return build_server_error_response("No User found in Redmine!", $response);
  }

  # Get Project ID from Issue in Redmine
  eval {
    my $sql_issue_id = "SELECT id, project_id FROM issues WHERE id = ?";
    $req->{project_id} = $db->selectrow_hashref($sql_issue_id, undef, $req->{issue_id})->{project_id};
  };
  if ($@) { return build_server_error_response("The issue does not exist!", $response) };


  if ($req->{hours} eq "") {
    return build_server_error_response("No spent time provided!", $response) 
  }

  if ($req->{comment} eq "") {
    return build_server_error_response("No comment provided!", $response) 
  }

  my $dt   = DateTime->now;
  my $db_parser = DateTime::Format::DBI->new($db);
  $req->{spent_on} = $db_parser->format_datetime($dt);

  $req->{activity_id} = 0;


  eval {
    my $sth = $db->prepare("INSERT INTO time_entries (project_id, activity_id, user_id, issue_id, hours, comments, spent_on, tyear, tmonth, tweek, created_on, updated_on) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, now(), now());");
    $sth->execute($req->{project_id}, $req->{activity_id}, $req->{user_id}, $req->{issue_id}, $req->{hours}, $req->{comment}, $req->{spent_on}, $dt->year(), $dt->month(), $dt->week_number());
    $rv = $db->last_insert_id(undef, "public", "time_entries", undef);
  };

  if ($@) {
    $response->header( -status => 500, -type => 'application/json', -charset => 'UTF-8' );
    $response->print( to_json({status => 'error', 'code' => 'server_error', msg => "Server error: $@", reg => $req}));
    return
  } 

  return to_json({status => 'success', id => $rv});

}



1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Author: %$AUTHOR%

Copyright (C) 2008-2013 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
