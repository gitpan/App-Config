use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'	     => 'App::Config',
    'VERSION_FROM'   => 'Config.pm', # finds $VERSION
    'MAN3PODS'       => { 
	# We must explicitly name Config.pm as a manifyable file because 
	# MakeMaker ignores files that match  /(config|setup).*\.pm/i;
	'Config.pm'  => '$(INST_MAN3DIR)/$(NAME).$(MAN3EXT)' 
    },
    'dist'           => { 
	'COMPRESS'   => 'gzip', 
	'SUFFIX'     => 'gz' 
    },
);
