#============================================================================
#
# App::Config.pm
#
# Perl5 module in which configuration information for an application can
# be stored and manipulated.  Configuration files and the command line can 
# be read and parsed, automatically updating the relevant variables.
#
# Written by Andy Wardley <abw@cre.canon.co.uk>
#
# Copyright (C) 1997 Canon Research Centre Europe Ltd.  All Rights Reserved.
#
#----------------------------------------------------------------------------
#
# $Id: Config.pm,v 1.3 1997/09/10 15:08:24 abw Exp abw $
#
#============================================================================

package App::Config;

require 5.004;
require AutoLoader;

use strict;
use vars qw( $RCS_ID $VERSION @ISA $AUTOLOAD );
use Carp;

$VERSION = sprintf("%d.%02d", q$Revision: 1.3 $ =~ /(\d+)\.(\d+)/);
$RCS_ID  = q$Id: Config.pm,v 1.3 1997/09/10 15:08:24 abw Exp abw $;
@ISA     = qw(AutoLoader);



#========================================================================
#                      -----  PUBLIC METHODS -----
#========================================================================

#========================================================================
#
# new($cfg)
#
# Module constructor.  Reference to a hash array containing configuration
# options may be passed as a parameter.  This is passed off to 
# _configure() for processing.
#
# Returns a reference to a newly created App::Config object.
#
#========================================================================

sub new {
    my $class = shift;
    my $self  = {};
    my $cfg   = shift;
    
    bless $self, $class;

    # internal hash arrays to store variable specification information
    $self->{ VARIABLE  } = { };  # variable values
    $self->{ DEFAULT   } = { };  # default values
    $self->{ ALIAS     } = { };  # known aliases  ALIAS => VARIABLE
    $self->{ CMDARG    } = { };  # cmd line argument pattern
    $self->{ ARGCOUNT  } = { };  # additional arg in cmd line?
    $self->{ EXPAND    } = { };  # expand vars, env vars, ~uid home dirs
    $self->{ VALIDATE  } = { };  # validation regex/array/function
    $self->{ ACTION    } = { };  # action function when variable is set
    
    # configure module 
    $self->_configure($cfg) if defined($cfg);

    return $self;
}



#========================================================================
#
# define($variable, $cfg)
#
# Defines the variable as a valid identifier and uses the values of the 
# configuration hash array, referenced by $cfg, to configure the various
# options for the variable.  A warning is issued (via _error()) if an
# invalid option is specified.
#
#========================================================================

sub define {
    my $self     = shift;
    my $variable = shift;
    my $cfg      = shift;


    # _varname returns variable name after aliasing and case conversion
    $variable = $self->_varname($variable);

    # activate $variable (so it does 'exist()') and set defaults
    $self->{ VARIABLE }->{ $variable } = undef;
    $self->{ EXPAND   }->{ $variable } = 1;

    # examine each variable configuration parameter
    foreach (keys %$cfg) {

	# DEFAULT, VALIDATE, EXPAND and ARGCOUNT are simple values
	/^(DEFAULT|VALIDATE|ARGCOUNT|EXPAND)$/i && do {
	    $self->{ uc $_ }->{ $variable } = $cfg->{ $_ };

	    next;
	};

	# ACTION should be a code ref
	/^ACTION$/i && do {
	    unless (ref($cfg->{ $_ }) eq 'CODE') {
		$self->_error("'$_' value is not a code reference\n");
		next;
	    };

	    # store code ref, forcing keyword to upper case
	    $self->{ uc $_ }->{ $variable } = $cfg->{ $_ };

	    next;
	};

	# ALIAS and CMDARG create a link to the variable name
	/^(ALIAS|CMDARG)$/i && do {
	    my $alias;

	    # cfg may be a single value or an array ref
	    foreach $alias (ref($cfg->{ $_ }) eq 'ARRAY' 
		    ?  @{ $cfg->{ $_ } }
		    : ( $cfg->{ $_ } )) {
    		$self->{ uc $_ }->{ $self->_varname($alias) } = $variable;
	    }

    	    next;
	};

	# default 
	$self->_error("$_ is not a valid configuration item\n");
    }

    # set variable to default value
    $self->default($variable);
}



#========================================================================
#
# default($variable)
#
# Sets the variable specified to the default value or undef if it doesn't
# have a default.  The default value is returned.
#
#========================================================================

sub default {
    my $self     = shift;
    my $variable = shift;

    # _varname returns variable name after aliasing and case conversion
    $variable = $self->_varname($variable);

#    $self->{ VARIABLE }->{ $variable } 
#    	    = $self->{ DEFAULT }->{ $variable } || undef;

    # set default with set(), triggering any set ACTION
    $self->set($variable, $self->{ DEFAULT }->{ $variable } || undef);
}



#========================================================================
#
# validate($variable, $value)
#
# Uses any validation rules or code defined for the variable to test if
# the specified value is acceptable.
#
# Returns 1 if the value passed validation checks, 0 if not.
#
#========================================================================

sub validate {
    my $self     = shift;
    my $variable = shift;
    my $value    = shift;
    my $validator;


    # _varname returns variable name after aliasing and case conversion
    $variable = $self->_varname($variable);

    # return OK unless there is a validation function
    return 1 unless defined($validator = $self->{ VALIDATE }->{ $variable });

    #
    # the validation performed is based on the validator type;
    #
    #   CODE ref: code executed, returning 1 (ok) or 0 (failed)
    #   SCALAR  : a regex which should match the value
    #

    # CODE ref
    ref($validator) eq 'CODE' && do {
    	# run the validation function and return the result
       	return &{ $self->{ VALIDATE }->{ $variable } }($variable, $value);
    };

    # non-ref (i.e. scalar)
    ref($validator) || do {
	# not a ref - assume it's a regex
	return $value =~ /$validator/;
    };
    
    # validation failed
    return 0;
}



#========================================================================
#
# get($variable)
#
# Returns the value of the variable specified, $variable.  Returns undef
# if the variable does not exists or is undefined and send a warning
# message to the _error() function.
#
#========================================================================

sub get {
    my $self     = shift;
    my $variable = shift;


    # _varname returns variable name after aliasing and case conversion
    $variable = $self->_varname($variable);

    # check the variable has been defined
    unless (exists($self->{ VARIABLE }->{ $variable })) {
	$self->_error("$variable: no such variable\n");
	return undef;
    }

    # return variable value
    $self->{ VARIABLE }->{ $variable } || undef;
}



#========================================================================
#
# set($variable, $value)
#
# Assigns the value, $value, to the variable specified.
#
# Returns 1 if the variable is successfully updated or 0 if the variable 
# does not exist.  If an ACTION sub-routine exists for the variable, it 
# will be executed and its return value passed back.
#
#========================================================================

sub set {
    my $self     = shift;
    my $variable = shift;
    my $value    = shift;


    # _varname returns variable name after aliasing and case conversion
    $variable = $self->_varname($variable);

    # check the variable exists
    unless (exists($self->{ VARIABLE }->{ $variable })) {
	$self->_error("$variable: no such variable\n");
	return 0;
    }

    # cast it in stone...
    $self->{ VARIABLE }->{ $variable } = $value;

    # ...and call any ACTION function bound to this variable
    return &{ $self->{ ACTION }->{ $variable } }($self, $variable, $value)
    	if (exists($self->{ ACTION }->{ $variable }));

    # ...or just return 1 (ok)
    return 1;
}



#========================================================================
#
# cfg_file($file)
#
# Reads and analyses the contents of $file and attempts to set variable
# values according to their definitions.
#
# Returns 1 on success, 0 on failure.
#
#========================================================================

sub cfg_file {
    my    $self   = shift;
    my    $file   = shift;
    local *CF;


    # bypass this sub-routine if a user-defined parser is defined
    return &{ $self->{ FILEPARSE } }($self, $file)
	if (defined($self->{ FILEPARSE }));


    # open and read config file
    open(CF, $file) or do {
	$self->_error("$file: $!\n");
	return 0;
    };

    while (<CF>) {
	chomp;

	# add next line if there is one and this is a continuation
	if (s/\\$// && !eof(CF)) {
	    $_ .= <CF>;
	    redo;
	}

	# ignore blank lines and comments
	next if /^\s*$/ || /^#/;

	# strip leading and trailing whitespace
	s/^\s+//;
	s/\s+$//;

	# call the user-defined line parser if defined
	if (defined($self->{ LINEPARSE })) {
	    # pass the $self Config object, filename, line number and line;
	    # if the function returns a true value, we continue onto the 
	    # next line;  a false result passes control down to the default
	    # line parser below...
    	    next if &{ $self->{ LINEPARSE } }($self, $file, $., $_);
	}

	# herein lies the default parser...

    	# split it up by whitespace (\s+) or "equals" (\s*=\s*)
  	if (/^([^\s=]+)(?:(?:(?:\s*=\s*)|\s+)(.*))?/) {
	    my ($variable, $value) = ($1, $2);

	    # _varname de-aliases and case converts where appropriate
	    $variable = $self->_varname($variable);

	    # check it's defined
	    unless (exists($self->{ VARIABLE }->{ $variable })) {
		$self->_error("$file:$.: no such variable: $variable\n");
		next;
	    }

	    # -- TODO --
	    # we may wish to use an ACCESS variable to determine if
	    # this variable can be updated by cfg_file();
	    # ---------

	    # unless we're expecting a parameter for this variable
	    # ($self->{ ARGCOUNT }->{ $variable } != 0), it's safe to default 
	    # a undef value to 1.  That is, assume "$variable" is euqivalent
	    # "$variable 1"
	    unless (defined($value)) {
    		$value = 1 
			unless defined($self->{ ARGCOUNT }->{ $variable })
			            && $self->{ ARGCOUNT }->{ $variable };
	    };

	    # expand embedded variables if EXPAND is defined
	    $value = $self->_expand($value) 
		    if defined($self->{ EXPAND }->{ $variable })
		            && $self->{ EXPAND }->{ $variable };

	    # look for any validation specified for the variable
	    if (defined($self->{ VALIDATE }->{ $variable })) {
		unless ($self->validate($variable, $value)) {
		    $self->_error("$file:$.: invalid data for '$variable'\n");
		    next;
		}
	    }

	    # finally set the variable
	    $self->set($variable, $value);

    	}
    	else {
	    $self->_error("$file:$.: parse error\n");
    	}
    }

    close(CF);

    # return ok status
    return 1;
}



#========================================================================
#
# cmd_line($argv)
#
# Examines the command-line options array, referenced by $argv, and 
# attempts to set variables accordingly.   The CMDARG and ARGCOUNT 
# variable parameters are used to determine which command line options
# refer to which variables and if they expect an additional argument,
# respectively.  The contents of the $argv list will be modified, with
# all processed options and arguments being shifted off the list.
#
# The contents of the CMDENV environment variable (if defined) are 
# whitespace-split and unshifted to the front of the @$argv array before
# processing starts.  Processing terminates if and when the ENDOFARGS 
# marker is encountered (--).
#
# Returns 1 on success, 0 on failure.
#
#========================================================================

sub cmd_line {
    my $self = shift;
    my $argv = shift;
    my ($arg, $variable, $value);


    # if a command line environment variable is defined, split this up
    # and unshift elements onto the front of the argv list
    unshift(@$argv, split(/\s+/, $ENV{ $self->{ CMDENV } }))
	if (defined($self->{ CMDENV }) && defined($ENV{ $self->{ CMDENV } }));

    # bypass this sub-routine if a user-defined parser is defined
    return &{ $self->{ CMDPARSE } }($self, $argv)
	if (defined($self->{ CMDPARSE }));

    # loop around arguments
    while (@$argv && $argv->[0] =~ /^-/) {
	$arg = shift(@$argv);

	# '--' (default) indicates the end of the options
	last if $arg eq $self->{ ENDOFARGS };

	# see if the cmd line arg is a known alias (CMDARG) to a variable
	if (defined($variable = $self->{ CMDARG }->{ $arg })) {

	    # call the user-defined line parser if defined
	    if (defined($self->{ ARGPARSE })) {
		# pass the $self Config object, current argument and reference 
		# to remaining argv list which may be modified by the parser 
		# (shifting off args);  if the function returns a true value, 
		# we continue onto the next argument;  a false result passes
		# control down to the default argument parser below...
		next if &{ $self->{ ARGPARSE } }($self, 
			$arg, $variable, $argv);
	    }

	    # we may wish to extend ARGCOUNT to handle nargs > 1
	    if ($self->{ ARGCOUNT }->{ $variable }) {
		# check there's a parameter and it's not another '-opt'
		if(defined($argv->[0]) && $argv->[0] !~ /^-/) {
		    $value = shift(@$argv);
		}
		else {
		    $self->_error("$arg expects an argument\n");
		    next;
		}
	    }
	    else {
		# simple flag
		$value = 1;
	    }

	    # look for any validation specified for the variable
	    if (defined($self->{ VALIDATE }->{ $variable })) {
		unless ($self->validate($variable, $value)) {
		    $self->_error("$arg $value: invalid data ($variable)\n");
		    next;
		}
	    }

	    # finally set the variable
	    $self->set($variable, $value);

	}
	else {
	    $self->_error("$arg : invalid flag\n");
	}
    }

    # return ok status
    return 1;
}



#========================================================================
#
# AUTOLOAD
#
# Autoload function called whenever an unresolved object method is 
# called.  If the method name relates to a defined VARIABLE, we patch
# in $self->get() and $self->set() to magically update the varaiable
# (if a parameter is supplied) and return the previous value.
#
# Thus the function can be used in the folowing ways:
#    $cfg->variable(123);     # set a new value
#    $foo = $cfg->variable(); # get the current value
#
# Returns the current value of the variable, taken before any new value
# is set.  Prints a warning if the variable isn't defined (i.e. doesn't
# exist rather than exists with an undef value) and returns undef.
#
#========================================================================

sub AUTOLOAD {
    my $self = shift;
    my $variable;
    my ($oldval, $newval);


    # splat the leading package name
    ($variable = $AUTOLOAD) =~ s/.*:://;

    # ignore destructor
    $variable eq 'DESTROY' && return;

    # _varname returns variable name after aliasing and case conversion
    $variable = $self->_varname($variable);

    # check we've got a valid variable
    $self->_error("$variable: no such variable\n"), return undef
	unless exists($self->{ VARIABLE }->{ $variable });

    # get the current value
    $oldval = $self->get($variable);

    # set a new value if a parameter was supplied
    $self->set($variable, $newval)
	if defined($newval = shift);

    # return old value
    return $oldval;
}



#========================================================================
#                      -----  PRIVATE METHODS -----
#========================================================================

#========================================================================
#
# _configure($cfg)
#
# Sets the various configuration options using the values passed in the
# hash array referenced by $cfg.
#
#========================================================================

sub _configure {
    my $self = shift;
    my $cfg  = shift;

    # set configuration defaults
    $self->{ FILEPARSE } = undef;  # user-defined fn to parse config file
    $self->{ LINEPARSE } = undef;  # "" for each config line
    $self->{ CMDPARSE  } = undef;  # "" for command line (@ARGV)
    $self->{ ARGPARSE  } = undef;  # "" for each arg in @ARGV
    $self->{ CMDENV    } = undef;  # env var for default cmd line opts
    $self->{ ERROR     } = undef;  # error handler function
    $self->{ CASE      } = 0;      # case sensitivity flag (1 = sensitive)
    $self->{ ENDOFARGS } = '--';   # end of cmd line arguments marker 

    # return now if there's nothing to do
    return unless $cfg;

    # check usage
    unless (ref($cfg) eq 'HASH') {
	$self->_error("%s->new expects a hash array reference\n", ref($self));
	return;
    };

    foreach (keys %$cfg) {

	# *PARSE and ERROR should be code refs
	/^(FILE|LINE|CMD|ARG)PARSE|ERROR$/i && do {

	    # check this is a code reference
	    unless (ref($cfg->{ $_ }) eq 'CODE') {
		$self->_error("\U$_\E parameter is not a code ref\n");
		next;
	    }

	    $self->{ "\U$_" } = $cfg->{ $_ };
	    next;
	};

	# CASE is a simple zero/non-zero evaluation
	/^CASE$/i && do {
	    $self->{ "\U$_" } = $cfg->{ $_ } ? 1 : 0;
	    next;
	};

	# CMDENV is a simple variable
	/^CMDENV|ENDOFARGS$/i && do {
	    $self->{ "\U$_" } = $cfg->{ $_ };
	    next;
	};

	# warn about invalid options
	$self->_error("\U$_\E is not a valid configuration option\n");
    }
}



#========================================================================
#
# _varname($variable)
#
# Variable names are treated case-sensitively or insensitively, depending 
# on the value of $self->{ CASE }.  When case-insensitive ($self->{ CASE } 
# != 0), all variable names are converted to lower case.  Variable values 
# are not converted.  This function simply converts the parameter 
# (variable) to lower case if $self->{ CASE } isn't set.  _varname() also 
# expands a variable alias to the name of the target variable.  
#
# The (possibly modified) variable name is returned.
#
#========================================================================

sub _varname {
    my $self = shift;
    my $variable = shift;

    # convert to lower case if case insensitive
    $variable = $self->{ CASE } ? $variable : lc $variable;

    # get the actual name if this is an alias
    $variable = $self->{ ALIAS }->{ $variable }
	if (exists($self->{ ALIAS }->{ $variable }));
   
    # return the variable name
    $variable;
}



#========================================================================
#
# _expand($value)
#
# The variable value string, $value, is examined and any embedded 
# variables, environment variables or tilde globs (home directories)
# are replaced with their respective values.
#
# The (possibly modified) value is returned.
#
#========================================================================

sub _expand {
    my $self  = shift;
    my $value = shift;
    my $home  = $ENV{ HOME } || (getpwuid($<))[7] || "";
    my $variable;


    # expand "~" or "~uid" home directory
    $value =~ s{^~([^/]*)} {
	    defined($1) && length($1)
	    ? (getpwnam($1))[7] || "~$1"
	    : $home
	}ex;

    # expand ${VAR} as environment variables
    $value =~ s/\$\{(\w+)\}/$ENV{ $1 } || ""/ge;

    # expand $(VAR) as a App::Config variable
    $value =~ s{\$\((\w+)\)} {
	    $self->{ VARIABLE }->{ $self->_varname($1) } || "";
	}gex;

    # finally try to expand any unparenthesised/braced variables,
    # e.g. "$var", as App::Config vars or environment variables
    $value =~ s{\$(\w+)} {
	    $self->{ VARIABLE }->{ $self->_varname($1) }
	    || $ENV{ $1 }
	    || ""
	}gex;

    # return the value 
    $value;
}



#========================================================================
#
# _error($format, @params)
#
# Checks for the existence of a user defined error handling routine and
# if defined, passes all variable straight through to that.  The routine
# is expected to handle a string format and optional parameters as per
# printf(3C).  If no error handler is defined, the message is formatted
# and passed to warn() which prints it to STDERR.
#
#========================================================================

sub _error {
    my $self   = shift;
    my $format = shift;

    # user defined error handler?
    if (defined($self->{ ERROR }) && ref($self->{ ERROR }) eq 'CODE') {
	&{ $self->{ ERROR } }($format, @_);
    }
    else {
	carp(sprintf($format, @_));
    }
}



#========================================================================
#
# _dump()
#
# Dumps the contents of the Config object.  Useful for debugging, but
# no other real purpose.
#
#========================================================================

sub _dump {
    my $self = shift;

    foreach (qw( FILEPARSE LINEPARSE CMDPARSE ARGPARSE ERROR )) {
	printf("%-10s => %s\n", $_, 
		defined($self->{ $_ }) ? $self->{ $_ } : "<undef>");
    }	    
    print "CASE       => ", 
	    $self->{ CASE } ? "sensitive" : "insensitive", "\n";

    print "VARIABLES\n";
    foreach (keys %{ $self->{ VARIABLE } }) {
	printf("  %-20s\n", $_);

	foreach my $param (qw( VARIABLE DEFAULT PARSE VALIDATE PARAM )) {
    	    printf("    %-9s: %s\n", $param, 
		    defined($self->{ $param }->{ $_ }) 
		       	? $self->{ $param }->{ $_ } 
			: "<undef>");
	}
	printf("    ARGCOUNT : %d\n", $self->{ ARGCOUNT }->{ $_ } ? 0 : 1);
    }

    print "ALIASES\n";
    foreach (keys %{ $self->{ ALIAS } }) {
	printf("    %-12s => %s\n", $_, $self->{ ALIAS }->{ $_ });
    }
    print "CMDARGS\n";
    foreach (keys %{ $self->{ CMDARG } }) {
	printf("    %-12s => %s\n", $_, $self->{ CMDARG }->{ $_ });
    }
} 


1;

__END__

=head1 NAME

App::Config - Perl5 extension for managing global application configuration information.

=head1 SYNOPSIS

    use App::Config;
    my $cfg = new App::Config;

    $cfg->define("foo");            # very simple variable definition

    $cfg->set("foo", 123);          # trivial set/get examples
    $fval = $cfg->get("foo");      
    
    $cfg->foo(456);                 # direct variable access 

    $cfg->cfg_file(".myconfigrc");  # read config file
    $cfg->cmd_line(\@ARGV);         # process command line

=head1 OVERVIEW

App::Config is a Perl5 module to handle global configuration variables
for perl programs.  The advantages of using such a module over the 
standard "global variables" approach include:

=over 4

=item *

Reduction of clutter in the main namespace.

=item *

Default values can be specified.

=item *

Multiple names (aliases) can refer to the same variable.

=item *

Configuration values can be set directly from config files and/or 
command line arguments.

=item *

Data values can be automatically validated by pattern matching (e.g. "\d+"
to accept digits only) or through user-supplied routines.

=item *

User-defined routines can be called automatically when configuration values
are changed.

=back

=head1 PREREQUISITES

App::Config requires Perl version 5.004 or later.  If you have an older 
version of Perl, please upgrade to latest version.  Perl 5.004 is known 
to be stable and includes new features and bug fixes over previous
versions.  Perl itself is available from your nearest CPAN site (see
http://www.perl.com/CPAN).

=head1 INSTALLATION

To install this module type the following:

    perl Makefile.PL
    make
    make install

This will copy App::Config.pm to your perl library directory for use by all
perl scripts.  You will probably need root access to do this.  You can now 
load the App::Config module into your Perl scripts with the line:

    use App::Config;

If you don't have sufficient privileges to install App::Config.pm in 
the Perl library directory, you can prefix all Perl scripts that call it 
with a line of the form:

    use lib '/user/abw/lib/perl5';  # wherever you put App::Config.pm
    use App::Config;

=head1 DESCRIPTION

=head2 CREATING A NEW APP::CONFIG OBJECT

    $cfg = new App::Config;

This will create a reference to a new App::Config with all configuration
options set to their default values.  You can initialise the object by 
passing a hash array reference containing configuration options:

    $cfg = new App::Config {
	CASE      => 1,
	FILEPARSE => \&my_parser,
	ERROR     => \&my_error,
    };

The following configuration options may be specified

=over 4

=item CASE

Determines if the variable names are treated case sensitively.  Any non-zero
value makes case significant when naming variables.  By default, CASE is set
to 0 and thus "Variable", "VARIABLE" and "VaRiAbLe" are all treated as 
"variable".

=item ERROR

Specifies a user-defined error handling routine.  A format string is 
passed as the first parameter, followed by any additional values, as
per printf(3C).

=item FILEPARSE

Specifies a user-defined routine for parsing a configuration file.  The
function is called by C<cfg_file()> and is passed a reference to
the App::Config object and the name of the file to parse.  The routine 
should update any variable values directly.  The return value is expected 
to be 1 to indicate success or 0 to indicate failure.  This value is 
returned directly from C<cfg_file()>;

Pseudo-Code Example:

    $cfg = new App::Config { FILEPARSE => \&my_parser };

    sub my_parser {
	my $cfg  = shift;
	my $file = shift;

	# open file, read lines, etc.
	# ...
	$cfg->set($variable, $value);  # set variable value 
	# close file, etc.

	return 1;
    }

=item LINEPARSE

Instead of providing a routine to parse the entire config file, LINEPARSE
can be used to define a function to handle each line of the config file.
The C<cfg_file()> routine reads the file and passes each line
to the LINEPARSE function, where defined.

Four parameters are passed to the LINEPARSE function; a reference to the
App::Config object, the config filename, the current line within the file 
and the line of text itself (the filename and line number are useful for 
reporting errors).  Note that C<cfg_file()> does some elementary 
pre-processing before calling the LINEPARSE function.  See 
L<READING A CONFIGURATION FILE> for more details.

The function should return 1 to indicate that the line has been successfully 
parsed, or 0 to indicate that no action was taken and the default line 
parser should now be used for this line.

=item CMDPARSE

Specifies a user-defined routine for parsing the command line.  The 
function is called by cmd_line() and is passed a reference 
to the App::Config object and a reference to a list of command line 
arguments (usually @ARGV).

The function is required to set variable values directly and return 
1 or 0 to indicate success or failure, as is described in the 
FILEPARSE section above.

=item ARGPARSE

Just as a LINEPARSE routine can be defined to parse each line of a config
file, an ARGPARSE routine can also be specified to parse each command line 
argument.  The function is called from cmd_line() and is passed a reference 
to the App::Config object through which variable values can be manipulated.  
Other parameters passed are the command line argument in question (e.g. 
C<"-v">), the name of the variable to which it corresponds (e.g. C<"verbose">) 
and a reference to the remaining argument list.  The function is expected 
to modify the argument list if necessary, shifting off additional parameters 
where required.

A pseudo-code example is shown:

    my $cfg = new App::Config { ARGPARSE => \&my_arg_parse, };	    

    sub my_arg_parse {
	my $cfg     = shift;
	my $arg     = shift;
	my $var     = shift;
	my $argvref = shift;

	VAR: {
	    $var eq 'verbose' && do {  
		$cfg->set($var, 1);
		last VAR;
	    };

	    # this time, look at $arg instead of $var
	    $arg eq '-f' && do {
		$cfg->set($var, shift(@$argvref));  # should error check
		last VAR;
	    };

	    # not interested in anything else
	    # (let default parser have a go)
	    return 0;
	}

	# we processed it so return 1
	return 1;
    }
		
=item CMDENV

The CMDENV option is used to specify the name of an environment variable
which may contain default command line options.  If defined, the variable
is examined by the cmd_line() routine where it is split into whitespace
separated tokens and parsed along with the rest of the command line options.
Environment variable options are processed before any real command line 
options.

Note that the variable is split on whitespace and does not take into 
account quoted whitespace.  Thus 'foo "bar baz" qux' will be split into 
the tokens 'foo', '"bar', 'baz"' and 'qux'.  This will be fixed in a 
future release.

From the Unix shell:

    $ SPLATOPTS="-z -f foobar"

Perl App::Config usage:

    my $cfg = new App::Config { CMDENV => "SPLATOPTS" };

    $cfg->cmd_line(\@ARGV);   # parses ("-z", "-f", "foobar", @ARGV)

=item ENDOFARGS

The ENDOFARGS option can be used to specify the marker that signifies the
end of the command line argument list.  Typically, and by default, this is
'--'.  Any arguments appearing in the command line after this token will be
ignored.

    my $cfg = new App::Config { ENDOFARGS => "STOP" };

    @args = qw(-f -g -h STOP -i -am -ignored);
    $cfg->cmd_line(\@args);

    # @args now contains qw(-i -am -ignored) 

=back

=head2 DEFINING VARIABLES

The C<define()> function is used to pre-declare a variable and specify 
its configuration.

    $cfg->define("foo");

In the simple example above, a new variable called "foo" is defined.  A 
reference to a hash array may also be passed to specify configuration 
information for the variable:

    $cfg->define("foo", {
	    DEFAULT   => 99,
	    ALIAS     => 'metavar1',
	});

The following configuration options may be specified

=over 4

=item DEFAULT

The DEFAULT value is used to initialise the variable.  The variable remains
set to this value unless otherwise changed via C<set()>, C<cfg_file()> or 
C<cmd_line()>.

=item ALIAS

The ALIAS option allows a number of alternative names to be specified for 
this variable.  A single alias should be specified as a string, multiple 
aliases as a reference to an array.  e.g.:

    $cfg->define("foo", {
	    ALIAS  => 'metavar1',
	});

or

    $cfg->define("bar", {
	    ALIAS => [ 'metavar2', 'metalrod', 'boozer' ],
	});

In the first example, C<$cfg-E<gt>set("metavar1")> (or any other 
variable-related function) is equivalent to C<$cfg-E<gt>set("foo")>.  
Likewise for the second example, with all 3 aliases defined.

=item CMDARG

When processing a list of command line arguments, flags may be used to 
refer to certain variable values.  For example, C<-v> is a common flag
indicating verbose mode.  The 'verbose' variable might be defined as 
such:

    $cfg->define("verbose", {
	    CMDARG => '-v',
	});

If the C<cmd_line()> function detects C<-v> in the command line arguments, 
it will update the 'verbose' value.  See also the ARGCOUNT option below 
which influences the variable values that are set by the command line 
processing function.

A variable may have more than one related command line argument.  These
can be specified by passing a reference to an array of arguments:

    $cfg->define("verbose", {
	    CMDARG => [ '-v', '-V' ],
	});

=item ARGCOUNT

Some variables are intended to be simple flags that have a false/true
(zero/non-zero) value (e.g. the 'verbose' example above) while others
may require mandatory arguments (e.g. specifying a file: C<"-f filename">).
The ARGCOUNT value is used to determine if an additional argument is 
expected (C<ARGCOUNT =E<gt> 1>) or not (C<ARGCOUNT =E<gt> 0>).

When ARGCOUNT is 1, C<cfg_file()> passes the rest of the config line (after
the opening variable name has been removed) as the argument value and 
C<cmd_line()> passes the next argument from the command line argument 
list (usually @ARGV).  When ARGCOUNT is 0, both functions pass the value 
1 to set the variable to a true state.  The default ARGCOUNT value is 0.

NOTE: Although any non-zero value can be used to indicate the presence of 
an additional argument, this option may be extended in the future to handle
multiple arguments.  The behaviour associated with any value other than 1 
or 0 may change in subsequent versions.

=item EXPAND

Variable values specified in a configuration file (see 
L<READING A CONFIGURATION FILE>) may contain environment variables, 
other App::Config variables and/or users' home directories specified 
in tilde notation (e.g. ~abw).  The EXPAND option specifies if these 
variables should be replaced with their relevant values.  By default
EXPAND is set to 1 (expansion) but can be set to 0 to disable the
feature.

Items are expanded according to the following rules:

=over 4

=item *

A directory element specified in tilde notation is expanded to the full
directory path it represents (e.g. ~abw/lib => /user/abw/lib).  A tilde
by itself expands to the home directory of the current user (e.g.
~/lib => /users/abw/lib).  If a non-existant user is specified or it is
not possible to determine the home directory of the user, the tilde 
notation is left unexpanded (e.g. ~nosuchuser/lib).

=item *

A variable enclosed in braces and prefixed with a dollar symbol (e.g.
${HOME}) is assumed to be an environment variable and is expanded as such.
A non-existant variable will be replaced by an empty string, as is typical 
in UNIX shell expansion (e.g. ${DUD}/lib => /lib).

=item *

A variable enclosed in parenthesis and prefixed with a dollar symbol (e.g.
$(ROOT)) is assumed to refer to another variable defined in the current 
App::Config object.  Case sensitivity is applied as per the current CASE
setting and non-existant variables are replaced by an empty string as per
environment variables (e.g. $(mipspelt)/lib => /lib).

=item *

A variable prefixed with a dollar and with no enclosing braces or 
parenthesis (e.g. $root/lib) is first interpreted as an App::Config 
variable and if not resolved, as an environment variable.  If the 
variable cannot be evaluated in either context it is ignored and the 
original text is left unmodified.

=back

=item VALIDATE

Each variable may have a sub-routine or regular expression defined which 
is used to validate the intended value that is set by C<cfg_file()> and 
C<cmd_line()>.

If VALIDATE is defined as a simple string, it is applied as a regular
expression to the value read from the config file or command line.  If
the regex matches, the value is set.  If not, a warning message is generated.

VALIDATE may also be defined as a reference to a sub-routine which takes
as its arguments the name of the variable and its intended value.  The 
sub-routine should return 1 or 0 to indicate that the value is valid
or invalid, respectively.  An invalid value will cause a warning error
message to be generated.

=item ACTION

The ACTION option allows a sub-routine to be bound to a variable that is
executed whenever the variable is set.  The ACTION is passed a reference
to the App::Config object, the name of the variable and the value of the 
variable.

The ACTION routine may be used, for example, to post-process variable data, 
update the value of some other dependant variable, generate a warning 
message, etc.

Example:

    sub my_notify {
	my $cfg = shift;
	my $var = shift;
	my $val = shift;

	print "$variable set to $value\n";
    }

Be aware that calling C<$cfg-E<gt>set()> to update the variable from within 
the ACTION function will cause a recursive loop as the ACTION function is 
repeatedly called.  This is probably a bug, certainly a limitation.

=item 

=back

=head2 READING AND MODIFYING VARIABLE VALUES

App::Config defines two methods to manipulate variable values: 

    set($variable, $value);
    get($variable);

Both functions take the variable name as the first parameter and C<set()>
takes an additional parameter which is the new value for the variable.
C<set()> returns 1 or 0 to indicate successful or unsuccessful update of the
variable value.  If there is an ACTION routine associated with the named
variable, the value returned will be passed back from C<set()>.  The 
C<get()> function returns the current value of the variable.

Once defined, variables may be accessed directly as object methods where
the method name is the same as the variable name.  i.e.

    $cfg->set("verbose", 1);

is equivalent to 

    $cfg->verbose(1); 

Without parameters, the current value of the variable is returned.  If
a parameter is specified, the variable is set to that value and the 
original value (before modification) is returned.

    $cfg->age(28);  
    $cfg->age(29);  # sets 'age' to 29, returns 28

=head2 READING A CONFIGURATION FILE

App::Config can be used to read configuration files and automatically 
update variable values based on the contents of the file.  

    $cfg->cfg_file("$HOME/.myapprc");

The C<cfg_file()> function reads each line of the specified configuration 
file and processes them according to the following rules:

=over 4

=item *

Any lines ending with a backslash '\' are treated as continuation lines.
The following line is appended to the current line (and any subsequent
continuation lines) before any further processing.

=item *

Any blank lines or lines starting with a '#' (i.e. comments) are ignored.

=item *

Leading and trailing whitespace is ignored.

=item *

The line is separated at the first whitespace character or at the first 
C<'='> character (surrounding whitespace is ignored).

=item *

A variable by itself with no corresponding value will be treated as a 
simple flag if it's ARGCOUNT is 0.  In this case, the value for the
variable will be set to 1.

=back

The following example demonstrates a typical configuration file:

    # simple flag (same as " verbose 1" or "verbose = 1")
    verbose

    # the following lines are all equivalent
    file     /tmp/foobar
    file  =  /tmp/foobar
    file=/tmp/foo

=head2 PARSING THE COMMAND LINE

By specify CMDARG values for defined variables, the C<cmd_line()> function
can be used to read the command line parameters and automatically set
variables.

When an command line argument matches a CMDARG value, the variable it 
relates to is updated.  If the variable has an ARGCOUNT of 0, it will be
assigned the value 1 (i.e. the flag is set).  A variable with an ARGCOUNT
of 1 will be set with the next value in the arguments.  Users familiar with
getopt(3C) will recognise this as equivalent to adding a colon after an
option letter (e.g. C<"f:">).  An error is generated if the argument starts
with a '-'.  The special option "--" may be used to delimit the end of the
options.  C<cmd_line()> stops processing if it finds this option.

Example variable definition:

    $cfg->define("verbose", {
	    CMDARG   => '-v',
	    ARGCOUNT => 0,      # default anyway
	});
    $cfg->define("file", {
	    CMDARG   => '-f',
	    ARGCOUNT => 1,      # expects an argument
	});

Command-line options:

    -v -f foobar

Variable values after calling C<cmd_line(\@ARGV)>:

    verbose: 1
    file:    foobar

=head1 KNOWN BUGS AND LIMITATIONS

The following list represents known limitations or bugs in App::Config
or ways in which it may be improved in the future.  Please contact the
author if you have any suggestions or comments.

=over 4

=item *

An ACTION sub-routine may not update its variable via the $cfg->set() 
method.  This causes the ACTION function to be re-executed, starting a 
recursive loop.

=item *

More extensive variable validation (not using user-defined functions),
perhaps by defining standard classes (e.g. numeric, filename, list, etc).
Variable validation may be also extended to allow manipulation of the
data as well (e.g. splitting a string into a list).

=item *

Further extend command line parsing.  Maybe allow regexes to be specified 
for matches (e.g. C<"-v(erbose)">) and handle different command line 
characters other than C<'-'> (e.g. C<+flag @file>).  This may also tie in 
with long (--) and short (-) options and defining recognised 'classes' of
options.  

=item *

ARGCOUNT should be able to indicate nargs > 1 and have cmd_line extract 
them accordingly.  Perhaps have types, e.g. boolean, single, multiple.
The validate function could additionally take an array ref which contains 
code refs or regex's to match each arg.  Should also be able to handle  
multiple options that can be specified separately, e.g. -I/usr/include 
-I/user/abw/include.  

=item *

An ACCESS parameter could specify which actions may update a variable:
set(), cfg_file() and/or cmd_line().

=item *

Allow variables to have related environment variables which are parsed by
an env_vars() function.

=back

=head1 AUTHOR

Andy Wardley, C<E<lt>abw@cre.canon.co.ukE<gt>>

SAS Group, Canon Research Centre Europe Ltd.

App::Config is based in part on the ConfigReader module, v0.5, by Andrew 
Wilcox (currently untraceable).

=head1 COPYRIGHT

Copyright (c) 1997 Canon Research Centre Europe Ltd.  All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

=over 4

=item Andy Wardley's Home Page

http://www.kfs.org/~abw/

=item The SAS Group Home Page

http://www.cre.canon.co.uk/sas.html

The research group at Canon Research Centre Europe responsible for 
development of App::Config and similar tools.

=item The ConfigReader module.

The module which provided inspiration and ideas for the development of 
App::Config.

=back

=cut
