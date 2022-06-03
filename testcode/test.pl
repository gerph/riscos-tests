#!/usr/bin/perl
##
# Build the test code to check that the toolchain works.
#
# We take a test script, conventionally called 'tests.txt', which
# contains:
#    A number of Group definitions
#    A number of Tests within those definitions
#
# Any definitions within the Group are inherited within the Test, and
# only acted on within the test (with a couple of exceptions).
#
# Groups are executed in order given in the description.
# Tests within the grounp in the order given in the description.
#
# Groups have names, to distinguish them from one another
# Tests have names, to distinguish them within the group.
#
# Tests will execute a command, using the supplied tool.
# The command (and many other of the parameters) may be parameterised
# to allow it to be run in different ways.
# Tests must return a given return code, or they will fail.
# Tests may be checked for specific output.
# Tests may check a single output file's content.
# Tests may be marked as disabled, to prevent them running, but keep
# them in the description.
#
# Checkers can be configured which check the content of generated
# files.
#
# Description file format:
#
# # at the start of a line marks a comment.
# Statements take the form:
#    <statement>: <argument>
#
# Group definitions start at a 'Group:' statement, and end with either a
# 'Test' statement, or another 'Group:' statement.
#
# Group: <group name>
#       - begins a Group
# Test: <test name>
#       - begins a Test definition
#
# When a Test definition is encountered, it begins with the same
# definitions as were present in the Group. Any subsequent statements
# will override the group statements. A statement may start with a '-'
# character (and have no argument) to remove any setting provided by the
# group.
#
# Statements currently defined are:
#
# Include: <filename>
#       - Include another file as if it were inline
# Group: <name>
#       - Begin a group definition
# Test: <name>
#       - Begin a test definition
# Command: <command>
#       - Command to execute
# Capture:
#       - What we capture from the command ('stdout', 'stderr', 'both'), default 'both'
# File: <source filename>
#       - Source filename to apply
# Args: <arguments>
#       - Arbitrary arguments that may be substituted into the
#         command line
# Expect: <expectation filename>
#       - File to compare the output to
# Replace: <replacements script filename>
#       - File containing a script of regular expressions and commands to
#         filter output before comparing to Expectation file. See the
#         section below on replacement scripts.
# Creates: <output file(s)>
#       - Specify a name of a file (or files, space separated) that is/are
#         expected to be created.
#         They will be removed before the test runs, and after it completes.
#         If they are not present, the test fails.
# Length: <length of the created file>
#       - Expected length of the created file; if it doesn't match, the
#         test will fail. Must match all files marked as Creates.
# Removes: <output file>
#       - Specify a name of a file that is expected to be removed.
#         An empty file will be created before the test run.
#         If the file is still there when the test completes, the test fails.
# Absent: <output file>
#       - Specify a name of a file that is expected to not be present.
#         If the file is there when the test completes, the test fails.
# RC: <return code expected>
#       - Expected return code; if it's different the test will fail
#         Otherwise, the test must return 0.
# Input: <input file>
#       - A file to supply as input to the tool
# InputLine: <line>
#       - A string to supply to the tool, which will be followed by
#         a newline
# Env: <variable>=<value
#       - Define an environment variable which will be set for the
#         test execution. May be repeated to set multiple variables.
# Disable: <message>
#       - Disable a test (or the group), with a message
# <checker>:<parameter>: <argument>
#       - Provide parameters to a specific checker.
#
# All of the arguments can have values substituted into them.
# The following substitutions are available:
#
#   $TOOL
#       - tool name, as supplied on the command line
#   $FILE
#       - filename, as supplied in the 'File' statement
#   $OFILE
#       - generated object file, in native format
#   $SFILE
#       - generated assembler file, in native format
#   $CFILE
#       - generated C file, in native format
#   $BASE
#       - base filename
#   $ARGS
#       - arguments, as supplied in the 'Args' statement
#   $ARG(1..)
#       - numbered arguments extracted from the .Args. statement
#
# Checkers are named by a short string, and contain parameters
# which can be used to confirm that the file was created correctly.
#
# Checkers and parameters:
#
# - 'aof' checker:
#
#   aof:totalareasize: <size>
#       - The sum of all the areas in the file
#
# - 'alf' checker:
#
#   alf:files: <number of files>
#       - The number of files in the library
#
# - 'elf' checker:
#
#   elf:endianness: little|big
#       - Check the endianess matches
#   elf:entry: <address>
#       - Address of the entry point
#   elf:type: <type>
#       - Object file type (1=> relative, 2=> executable)
#   elf:osabi: <version>
#       - OS/ABI version number (0=> no special interpretation, 64=> uses symbol versioning)
#   elf:phoff: <offset>
#       - Program header offset
#   elf:shoff: <offset>
#       - Section header offset
#   elf:ehsize: <offset>
#       - ELF header size (should always be 52)
#   elf:flags: <flags>
#       - Flags; for ARM these are a bitfield (not interpreted here)
#   elf:phentsize: <size>
#       - Size of each program header entry
#   elf:phnum: <count>
#       - Number of program header entries
#   elf:shentsize: <size>
#       - Size of each sectionheader entry
#   elf:shnum: <count>
#       - Number of section header entries
#   elf:shstrndx: <count>
#       - Index of the string section header
#
#    See:
#       http://infocenter.arm.com/help/topic/com.arm.doc.ihi0044f/IHI0044F_aaelf.pdf
#
# - 'text' checker:
#
#   text:matches: <filename>
#       - File to compare the content against
#   text:replace: <replacement file>
#       - File containing regular expressions to replace before
#         comparing to the matches file
#
# - 'binary' checker:
#
#   binary:matches: <filename>
#       - File to compare the content against (which must match exactly)
#   binary:checkfile: <filename>
#       - Check parts of the file according to a 'checkfile' containing
#         lines describing the checks to perform, in the form:
#           <offset> [word|byte|string>: <value>
#
# Replacement script syntax:
#
# Replacement scripts are intended to process an output from the tool to give an output
# which is able to be processed as an expectation. The script is similar in intent to
# the `sed` tool.
#
#   - Lines starting with a '#' character, or containing only whitespace are ignored.
#   - Each script contains line (called rules) which will be executed on every line of
#     the processed file.
#   - If the end of the rules is reached for a line, the line will be included within
#     the output.
#   - Directives are prefixed by a '%' symbol. Supported directives:
#       - `include <file>`
#   - Rules comprise two parts:
#       - Conditions (the first part of the line)
#       - Actions (the latter part of the line)
#   - Conditions:
#       - [<number>]-[<number>] or <number> for line range to apply rule to.
#         Line numbers start at 1.
#       - /<regular expression>/for expression to match.
#       - Both the above conditions may be suffixed by `!` to negate matches.
#   - Actions:
#       - `p` immediately include the line in the output, and move on to the next line
#       - `q` immediately terminate all input processing (ends the output without this line).
#       - `s/<from>/<to>/<options>` to perform a replacement on the content of the line.
#       - `d` skip this line, and move on to the next line.
#


# NOTE: This script is expected to run under perl 5.001, on RISC OS, as well as on
#       modern perls on Linux and MacOS. As such a few allowances have been made:
#           * The BEGIN block, below, allows us to not have the warnings or strict
#             packages available.
#           * The 'for' statements do not include the 'my' which is expected on later
#             perl version, as it is implicit in the earlier versions.
#           * mkdir must always be called with an octal mode.
if ($^O ne '' && $^O ne 'riscos')
{
    BEGIN {
        eval "use warnings;";
        eval "use strict;";
    }

    BEGIN {
        eval "use Time::HiRes qw(time);";
    }
}

my $testtool = undef;
my $dir = undef;
my $riscos = ($^O eq '' || $^O eq 'riscos');

# IF they want help.
my $help = 0;

# Whether we're debugging
my $debug_filename = 0;
my $debug_replace = 0;
my $debug_aof = 0;

# Matching for test selection
my $matchgroup_re = undef;
my $matchtest_re = undef;

# Verbose output?
my $verbose = 1;
my $showcmd = 0;

# Output controls
my $outputdump = 0;
my $outputsavedir = undef;

# Name of the test script to execute
my $testscript = $riscos ? "tests/txt" : "tests.txt";

# Colour configuration
my $reset_colour = "\e[0m";
my $fail_colour = "\e[31m";
my $crash_colour = "\e[35m";
my $ok_colour = "\e[32m";

if ($riscos)
{
    # We can't use the ANSI escapes on RISC OS.
    if (0)
    {
        # This doesn't work properly; it gets written as escape characters.
        $reset_colour = "\x11\x07";
        $fail_colour = "\x11\x01"; # Hopefully red
        $crash_colour = "\x11\x05"; # Hopefully purple
        $ok_colour = "\x11\x04"; # Hopefully green
    }
    else
    {
        $reset_colour = "";
        $fail_colour = "";
        $crash_colour = "";
        $ok_colour = "";
    }
}

# Generate Junit XML at the end? (the filename)
my $junitxml = undef;

my $arg;
while ($arg = shift)
{
    if ($arg =~ /^--?(.*)$/)
    {
        my $switch = $1;
        if ($switch eq 'h' || $switch eq 'help')
        {
            $help = 1;
        }
        elsif ($switch eq 'v' || $switch eq 'verbose')
        {
            $verbose = 1;
        }
        elsif ($switch eq 'q' || $switch eq 'quiet')
        {
            $verbose = 0;
        }
        elsif ($switch eq 'show-command')
        {
            $showcmd = 1;
        }
        elsif ($switch eq 'show-output')
        {
            $outputdump = 1;
        }
        elsif ($switch eq 'save-output')
        {
            $outputsavedir= shift;
        }
        elsif ($switch eq 'junitxml')
        {
            $junitxml = shift;
        }
        elsif ($switch eq 'script')
        {
            $testscript = shift;
        }
        elsif ($switch eq 'group')
        {
            $matchgroup_re = shift;
        }
        elsif ($switch eq 'test')
        {
            $matchtest_re = shift;
        }
        elsif ($switch eq 'debug')
        {
            my @debug = split /, */, shift;
            for $debugname (@debug)
            {
                if ($debugname eq 'filename' || $debugname eq 'all')
                { $debug_filename = 1; }
                if ($debugname eq 'replace' || $debugname eq 'all')
                { $debug_replace = 1; }
                if ($debugname eq 'aof' || $debugname eq 'all')
                { $debug_aof = 1; }
            }
        }
        else
        {
            die "Unrecognised switch: $arg\n";
        }
    }
    elsif (!defined $testtool)
    { $testtool = $arg; }
    elsif (!defined $dir)
    { $dir = $arg; }
    else
    {
        die "Extra argument not understood: $arg\n";
    }
}

if (!defined $testtool ||
    !defined $dir ||
    $help)
{
    print "Syntax: $0 [<options>] <test tool> <dir>\n";
    print "Options:\n";
    print "    -verbose         Verbose output\n";
    print "    -quiet           Not verbose output\n";
    print "    -script <script> Script file to read (default: 'tests.txt')\n";
    print "    -group <re>      Regular expression to match for group name\n";
    print "    -test <re>       Regular expression to match for test name\n";
    print "    -show-command    Show command executed\n";
    print "    -show-output     Show output on failure\n";
    print "    -save-output <dir>   Save all output to a directory\n";
    print "    -debug <type>    Enable debug types as comma-separated list\n";
    exit($help ? 0 : 1);
}

my $extensions_dir_re = "s|hdr|c|h|cmhg|s_c|o|aof|bin|x";
my $extensions_re = "xml|log|txt";

my ($none, $testtoolname) = ($testtool =~ /(^|\/)([^\/]*)$/);

# The parameters that are plain keys
my %testparams = map { $_ => '$' } (
        'command',
        'capture',
        'expect',
        'disable',
        'creates',
        'length',
        'removes',
        'absent',
        'rc',
        'file',
        'args',
        'replace',
        'input',
        'inputline',
    );
# The parameters that are lists ('@') or hashes ('%')
$testparams{'env'} = '%';


my %checkers = (
        'text' => \&text_check,
        'aof' => \&aof_check,
        'alf' => \&alf_check,
        'elf' => \&elf_check,
        'binary' => \&binary_check,
    );

my $dirsep;
if ($^O eq 'riscos')
{
    $dirsep = '.';
}
else
{
    $dirsep = '/';
}
my $tempbase;
if ($riscos)
{
    $tempbase = "<Wimp\$ScrapDir>.tt-$$";
}
else
{
    $tempbase = "/tmp/tt-$$";
}
my %tempnames = ();


END {
    for $name (keys %tempnames)
    {
        unlink $name;
    }
}

##
# Create a temporary filename.
sub tempfilename
{
    my ($name) = @_;
    my $filename = "$tempbase-$name";
    $tempnames{$filename} = 1;
    return $filename;
}


##
# Parse a test file, accumulating results in our structures.
#
# @param $testscript:   The script to read.
#
# @return:  An array containing the group of tests we want to run
sub parse_test_script
{
    my ($testscript) = (@_);
    my $group = undef;
    my $test = undef;
    my $acc = undef;
    my @lines;
    my @groups;
    open(TESTFH, "< $testscript") || die "Cannot open test script '$testscript': $!";
    while (<TESTFH>)
    {
        chomp;
        next if (/^ *#/ || /^ *$/);

        push @lines, $_;
    }
    close(TESTFH);

    my $line;
    for $line (@lines)
    {
        my $checker;
        my $minus;
        my ($cmd, $arg) = ($line =~ /^([A-Za-z]+): +(.*?) *$/);
        if (!$cmd)
        {
            ($minus, $cmd) = ($line =~ /^(-?)([A-Za-z]+):$/);
        }
        if (!$cmd)
        {
            # Not a base command specification; so try a checker value.
            ($checker, $cmd, $arg) = ($line =~ /^([A-Za-z]+):([A-Za-z]+): *(.*?) *$/);
            $checker = lc $checker;
            if (!defined $checkers{$checker})
            {
                die "Unrecognised checker '$checker' in line '$line' whilst reading '$testscript'";
            }
        }

        if (!$cmd)
        {
            die "Cannot understand line '$line' whilst reading '$testscript'";
        }

        if (defined $checker)
        {
            if (!defined $acc->{$checker})
            {
                $acc->{$checker} = {};
            }
            $acc->{$checker}->{lc $cmd} = $arg;
        }
        elsif ($cmd eq 'Include')
        {
            # Process an include file
            push @groups, parse_test_script($arg);
        }
        elsif ($cmd eq 'Group')
        {
            $group = {
                    'group-index' => scalar(@groups),
                    'group' => $arg,
                    'tests' => [],
                    'pass' => 0,
                    'fail' => 0,
                    'crash' => 0,
                    'skip' => 0,
                };
            delete $acc->{'tests'} if (defined $acc);
            $test = undef;
            $acc = $group;
            push @groups, $group;

            if ($matchgroup_re && $group->{'group'} !~ /$matchgroup_re/)
            {
                $group->{'skip'} = 1;
            }
        }
        elsif ($cmd eq 'Test')
        {
            $test = {
                    %$group,
                    'test-index' => scalar(@{$group->{'tests'}}),
                    'name' => $arg,
                    'duration' => undef,
                };
            for $key (keys %$test)
            {
                if (ref($test->{$key}) eq 'HASH')
                {
                    # If the element was a hash, copy it.
                    $test->{$key} = { %{$test->{$key}} };
                }
                elsif (ref($test->{$key}) eq 'ARRAY')
                {
                    # And same if it was a list
                    $test->{$key} = [ @{$test->{$key}} ];
                }
            }
            push @{$group->{'tests'}}, $test;
            delete $test->{'tests'};
            $acc = $test;

            if ($matchtest_re && $test->{'name'} !~ /$matchtest_re/)
            {
                $test->{'skip'} = 1;
            }
        }
        elsif (defined($testparams{lc $cmd}))
        {
            $cmd = lc $cmd;
            if ($minus)
            {
                undef $acc->{$cmd};
            }
            else
            {
                if ($testparams{$cmd} eq '@')
                {
                    if (!defined $acc->{$cmd})
                    {
                        $acc->{$cmd} = [];
                    }
                    push @{$acc->{$cmd}}, $arg
                }
                elsif ($testparams{$cmd} eq '%')
                {
                    if (!defined $acc->{$cmd})
                    {
                        $acc->{$cmd} = {};
                    }
                    my ($key, $value) = split(/=/, $arg, 2);
                    $acc->{$cmd}->{$key} = $value;
                }
                else
                {
                    $acc->{$cmd} = $arg;
                }
            }
        }
        else
        {
            die "Unknown command '$cmd' in '$line'";
        }
    }

    return @groups;
}

sub setup_variables
{
    my ($test) = @_;
    my $vars = {};

    $vars->{'TOOL'} = $testtool;
    $vars->{'FILE'} = $test->{'file'} || '';
    $vars->{'ARGS'} = defined($test->{'args'}) ? $test->{'args'} : '';
    my @args = split / +/, $vars->{'ARGS'};
    my $argn = 1;
    for $arg (0..8)
    {
        my $value = $args[$arg];
        $vars->{'ARG' . $argn} = defined $value ? $value : '';
        $argn++;
    }
    if (!$test->{'file'})
    {
        $vars->{'OFILE'} = '';
        $vars->{'SFILE'} = '';
        $vars->{'CFILE'} = '';
        $vars->{'HFILE'} = '';
        $vars->{'BASE'} = '';
    }
    elsif ($test->{'file'} =~ /(^|.*\.)($extensions_dir_re)\.(.*)/)
    {
        $vars->{'OFILE'} = "$1o.$3";
        $vars->{'SFILE'} = "$1s.$3";
        $vars->{'CFILE'} = "$1c.$3";
        $vars->{'HFILE'} = "$1h.$3";
        $vars->{'BASE'} = "$3";
    }
    elsif ($test->{'file'} =~ /^(^|.*\/)($extensions_dir_re)\/(.*)/)
    {
        $vars->{'OFILE'} = "$1o/$3";
        $vars->{'SFILE'} = "$1s/$3";
        $vars->{'CFILE'} = "$1c/$3";
        $vars->{'HFILE'} = "$1h/$3";
        $vars->{'BASE'} = "$3";
    }
    else
    {
        die "Unrecognised filename format: '$test->{'file'}'"
    }

    return $vars;
}


##
# Perform escaping on a string.
#
# The parameter is expected to be a command which we expect to be executed, almost verbatim.
# Quotes may be included around a parameter to ensure that it is not split.
# Any special characters will be escaped so that the shell passes them on.
#
# That is, the command line is as close to RISC OS format as is possible.
#
# @param $param         What to escape
# @param $escapetype    How to escape:
#                           0 => not at all
#                           1 => shell escaping
sub escape_parameters
{
    my ($param, $escapetype) = @_;
    if (defined $escapetype && $escapetype == 1)
    {
        #print "ESCAPING: '$param'\n";
        my @params = ($param =~ /([^" ]+|"(?:\\"|[^"])*"|[^ ]+)/g);
        my @newparams = ();
        push @newparams, shift(@params);
        for $part (@params)
        {
            #print "PART: '$part'\n";
            if ($part =~ /^"(?:\\"|[^"])*"$/)
            {
                # This is a quoted string, so we need to escape anything that would
                # cause the shell problems.
                if ($riscos)
                {
                    # Nothing to do.
                }
                else
                {
                    $part =~ s/([\$])/\\$1/g;
                }
            }
            else
            {
                # This is a bare string or one that isn't quoted as expected,
                # so we need to escape anything that would cause it problems.
                if ($riscos)
                {
                    # Nothing to do.
                }
                else
                {
                    $part =~ s/([^a-zA-Z_\-+0-9\/\.,])/\\$1/g;
                }
            }
            push @newparams, $part;
        }
        $param = join(' ', @newparams);
    }
    return $param;
}

sub substitute
{
    my ($str, $vars) = @_;
    return $str if (!defined $str);

    # Perl 5.0 doesn't support negative look behind, so the escaping with \$ isn't easy
    # to capture with a single regex, so we go to a lot of trouble to split the string up
    # and process individual variables.
    my @parts = split /\$/, $str;
    my $escape = 0;
    # For some reason Perl trims off any trailing elements if the split string appears
    # at the end of the list. So we put them back as empty elements.
    my ($trail) = ($str =~ /(\$+)$/);
    if ($trail)
    {
        for $i (1..length($trail))
        {
            push @parts, '';
        }
    }
    for $i (0..$#parts)
    {
        if ($escape)
        {
            $parts[$i - 1] =~ s/\\$/\$/;
        }
        elsif ($i != 0)
        {
            if ($parts[$i] =~ s/^([A-Z]+[0-9]*)/(defined($vars->{$1}) ? $vars->{$1} : '$' . $1)/e)
            {
                # We performed the replacement.
            }
            else
            {
                # The value wasn't actually a variable, so put the dollar back
                $parts[$i] = '$' . $parts[$i];
            }
        }
        $escape = ($parts[$i] =~ /\\$/);
    }
    $str = join "", @parts;
    return $str;
}

sub number
{
    my ($str) = @_;
    return undef if (!defined $str);

    if ($str =~ /^(0x|&)([0-9a-fA-F]+)$/)
    {
        return hex($2);
    }
    return $str;
}

sub native_filename
{
    my ($filename) = @_;

    die "No filename passed to native_filename" if (!defined $filename);

    print "('$filename'" if ($debug_filename);
    # First the directory exchanges
    if ($filename =~ /^(.*)\/($extensions_dir_re)$/)
    { # Unix layout, RISC OS syntax
        $filename = "$2$dirsep$1";
    }
    elsif ($filename =~ /^(.*)\.($extensions_dir_re)$/)
    { # Unix layout, Unix syntax
        $filename = "$2$dirsep$1";
    }
    elsif ($filename =~ /^($extensions_dir_re)\/(.*)$/)
    { # RISCO OS layout, Unix syntax
        $filename = "$1$dirsep$2";
    }
    elsif ($filename =~ /^($extensions_dir_re)\.(.*)$/)
    { # RISC OS layout, RISC OS syntax
        $filename = "$1$dirsep$2";
    }

    # Now the replacements for the plain extension
    # FIXME: I think this should probably also be performed on the prefix
    #        in the above names.
    elsif ($filename =~ /^(.*)\/($extensions_re)$/)
    {
        # RISCOS extension layout
        if ($^O eq 'riscos')
        {
            # Nothing to do; we're already in the right format
        }
        else
        {
            while ($filename =~ s/([^\^\@\$\%\\\.]+)\.\^\.//)
            {
                # Strip off <dir>.^ from any components
            }
            # Exchange the dots and slashes.
            $filename =~ tr!./!/.!;

            # Any ^ that are left will be for the root, so replace these
            $filename =~ s!\^/!../!g;

            # Environment variables <sigh>
            $filename =~ s/<(.*)\$Dir>/$ENV{uc "$1_DIR"} || die "No variable '$1' in '$filename'"/ieg;
        }
    }
    elsif ($filename =~ /^(.*)\.($extensions_re)$/)
    {
        # Unix extension layout
        if ($^O eq 'riscos')
        {
            # Convert to RISC OS format

            # Exchange the dots and slashes.
            $filename =~ tr!./!/.!;

            while ($filename =~ s!//\.!^.!)
            {
                # Replace all the ../ with ^.
            }
        }
        else
        {
            # Already in the correct format.
        }
    }
    print " => '$filename' : $dirsep)" if ($debug_filename);

    # Filename is now in Unix layout, using native syntax
    return $filename;
}

##
# Read a file, given a possibly RISC OS filename.
#
# @param $expect    Filename to read
# @param $label     What the file is, for reporting errors
#
# @return file content.
sub read_file
{
    my ($expect, $label) = @_;
    $expect = native_filename($expect);
    my $expected = '';
    if (-f "$expect")
    {
        open(FH, "< $expect") || die "Cannot read $label '$expect': $!";
        while (<FH>)
        { $expected .= $_; }
        close(FH);
    }
    return $expected;
}

##
# Read a command file with directives and comments.
#
# @param $filename      Filename to process
#
# @return list of lines, having processed directives
sub read_command_file
{
    my ($filename) = @_;
    local *FH;
    open(FH, "< $filename") || die "Cannot read file '$filename': $!";

    my @lines;
    while (<FH>)
    {
        chomp;
        next if (/^\s*$/ || /^#/);

        # Process directives
        if (/^%([a-z]+) ?(.*)$/)
        {
            my ($directive, $args) = ($1, $2);
            if ($directive eq 'include')
            {
                my $nextfile = $args;
                my $dir = $filename;
                # FIXME: This isn't platform aware.
                $dir =~ s/\/([^\/]*)$//;
                $nextfile = "$dir/$nextfile";
                push @lines, read_command_file($nextfile);
            }
            next;
        }
        push @lines, $_;
    }
    close(FH);
    return @lines;
}


##
# Apply a replacements file that contains simple replacements to fix up text.
#
# @param $replacements  Filename containing replacements
# @param $output        The output to perform replacement on
#
# @return New output, with replacements applied.
sub apply_replacements
{
    my ($replacements, $output) = @_;
    if (!-r "$replacements")
    { die "Cannot read replacements file '$replacements': $!"; }
    # Read in all the replacement lines, so that we can process them for the content.
    my @replacement_lines = read_command_file($replacements);

    my @replacement_code;
    for $line (@replacement_lines)
    {
        my @conditions;
        my @actions;
        # Conditions for line numbers
        if ($line =~ s!^([0-9]+|-[0-9]+|[0-9]+-[0-9+]) +!!)
        {
            # Applies to given lines
            my $range = $1;
            my $first = undef;
            my $last = undef;
            my $condition;
            if ($range =~ /^[0-9]+$/)
            { $condition = "\$index == $range"; }
            elsif ($range =~ /^-([0-9]+)$/)
            { $condition = "\$index <= $1"; }
            elsif ($range =~ /^([0-9]+)-([0-9]+)$/)
            { $condition = "\$index >= $1 && \$index <= $2"; }
            elsif ($range =~ /^([0-9]+)-$/)
            { $condition = "\$index >= $1"; }

            if ($line =~ s/^! *//)
            {
                $condition = "! ($condition)";
            }
            push @conditions, $condition;
        }

        # Conditions for regular expression matches
        if ($line =~ s!^([^a-zA-Z0-9])(.*[^\\]|)\1 +\! *!!)
        {
            my ($delimiter, $match) = ($1, $2);
            my $condition = "\$line !~ m$delimiter$match$delimiter";
            push @conditions, $condition;
        }
        elsif ($line =~ s!^([^a-zA-Z0-9])(.*[^\\]|)\1 +!!)
        {
            my ($delimiter, $match) = ($1, $2);
            my $condition = "\$line =~ m$delimiter$match$delimiter";
            push @conditions, $condition;
        }

        # Replacement action
        my $action = 'die "undefined action!\n";';
        if ($line =~ m!^s([^a-zA-Z0-9])(.*[^\\]|)\1(.*[^\\]|)\1([mgs]?i?)$!)
        {
            my $sym = $1;
            my $from = $2;
            my $to = $3;
            my $opts = $4;

            $from =~ s/\\$sym/$sym/g;
            $to =~ s/\\$sym/$sym/g;

            print "REPLACE: '$from' => '$to' '$opts'\n" if ($debug_replace);
            $to =~ s!\/!\\/!g;
            $from =~ s!/!\\/!g;
            $action = "\$line =~ s/$from/$to/$opts;";
        }

        # Delete action
        elsif ($line =~ m!^d$!)
        {
            $action = "next;";
        }
        elsif ($line =~ m!^p$!)
        {
            $action = "\$content .= \"\$line\\n\";\nnext;";
        }
        elsif ($line =~ m!^q$!)
        {
            $action = 'last;';
        }
        else
        {
            die "Unrecognised action line: '$line'";
        }

        # Build the replacement code.
        my $code = '';
        my $indent = '  ';
        if (@conditions)
        {
            $code .= $indent . "if (" . join(' && ', @conditions) . ")\n$indent" . "{\n";
            $indent .= '  ';
        }
        $action =~ s/\n/\n$indent/g;
        $code .= "$indent$action\n";
        if (@conditions)
        {
            $code .= "  }\n";
        }
        push @replacement_code, $code;
    }

    # Wrap the replacement code with the line iteratation
    local $text = $output;
    my $code = "my \$index = 0;\n";
    $code .= "my (\$trailingblanks) = (\$text =~ /(\\n+)\$/);\n";
    $code .= "my \@extralines;\n";
    $code .= "if (length(\$trailingblanks || '') > 0)\n";
    $code .= "{ \@extralines = (('') x (length(\$trailingblanks || '') - 1)); }\n";
    $code .= "for \$line ((split /\\n/, \$text), \@extralines)\n{\n";
    $code .= "  \$index++;\n";
    #$code .= "  print \"LINE \$index: \$line\\n\";\n";
    $code .= join("\n", @replacement_code);
    if (@replacement_code)
    {
        $code .= "\n";
    }
    $code .= "  \$content .= \"\$line\\n\";\n";
    $code .= "}\n1;\n";

    print "SCRIPT:\n$code\n" if ($debug_replace);

    # Run the replacements
    #print "INPUT:\n$output\n" if ($debug_replace);
    my $content = '';
    eval $code || die "Evaluation of replacements failed: $@";
    #print "RESULT:\n$content\n" if ($debug_replace);

    return $content;
}

##
# Run a specified test.
#
# Uses the parameters in the test to determine how the test should
# be run.
#
# @param $test      Test parameters
#
# @retval 0     Test passed
# @retval 1     Test failed for some reason
# @retval 2     Test crashed (signal generated)
# @retval -1    Test skipped

sub run_test
{
    my ($test) = @_;
    my $vars = setup_variables($test);

    my $name = $test->{'name'};
    my $disable = substitute($test->{'disable'}, $vars);
    my $cmd = substitute($test->{'command'}, $vars);
    my $capture = substitute($test->{'capture'} || 'both', $vars);
    my $creates = substitute($test->{'creates'}, $vars);
    my $absent = substitute($test->{'absent'}, $vars);
    my $removes = substitute($test->{'removes'}, $vars);
    my $length = substitute($test->{'length'}, $vars);
    my $expect = substitute($test->{'expect'}, $vars);
    my $replacements = substitute($test->{'replace'}, $vars);
    my $wantrc = substitute($test->{'rc'}, $vars) || 0;
    my $input = substitute($test->{'input'}, $vars);
    my $inputline = substitute($test->{'inputline'}, $vars);

    $length = number($length);

    if (defined($creates))
    {
        my @create_list = split / +/, $creates;
        for $created (@create_list)
        {
            $created = native_filename($created);
            unlink $created if (-f $created);
            rmdir $created if (-d $created);
        }
    }
    if (defined($removes))
    {
        $removes = native_filename($removes);
        # We create the file to check that it's not there at the end.
        open(FH, "> $removes") || die "Cannot create '$removes' for 'removes' check: $!";
        close(FH);
    }

    printf '  %-34s : ', $name;

    if ($disable)
    {
        # They requested this test not run for a reason.
        $test->{'skip'} = 1;
        $test->{'result'} = 'skip';
        $test->{'result_message'} = $disable;
        print "SKIP: $disable\n";
        return -1;
    }

    my $cmdtorun = $cmd;
    if (!defined $cmd)
    {
        $test->{'result'} = 'crash';
        $test->{'result_message'} = "No command defined";
        print "${crash_colour}MISCONFIGURED: No command defined${reset_colour}\n";
        return 2;
    }

    # Escape the command's parameters
    $cmdtorun = escape_parameters($cmdtorun, 1);

    # FIXME: Probably not correct for RISC OS?
    if ($riscos)
    {
        if ($capture ne 'both')
        {
            die "Bad 'capture' specification: must be 'both' on RISC OS, not '$capture'\n";
        }
    }
    else
    {
        if ($capture eq 'stdout')
        {
            $cmdtorun .= ' 2> /dev/null';
        }
        elsif ($capture eq 'stderr')
        {
            $cmdtorun .= ' 2>&1 > /dev/null';
        }
        elsif ($capture eq 'both')
        {
            $cmdtorun .= ' 2>&1';
        }
        else
        {
            die "Bad 'capture' specification: must be 'stdout', 'stderr' or 'both', not '$capture'\n";
        }
        if ($cmdtorun !~ / 2>/)
        {
            $cmdtorun .= ' 2>&1';
        }
    }
    if (defined $input)
    {
        $input = native_filename($input);
    }
    elsif (defined $inputline)
    {
        $input = tempfilename('input');
        my $inputactual = $inputline;
        $inputactual =~ s/\\n/\n/g;
        $inputactual =~ s/\\x([0-9A-Fa-f][0-9A-Fa-f])/chr(hex($1))/ge;
        open(INFH, "> $input") || die "Cannot create temporary input file '$input': $!";
        print INFH "$inputactual\n";
        close(INFH);
    }
    if (defined $input)
    {
        # FIXME: Probably not correct for RISC OS?
        $cmdtorun .= " < $input";
    }

    my $output;
    my $duration = undef;
    my $status;
    {
        my $start_time = time();

        # Set up the environment that we run the command under.
        my %oldenv = ();
        if (defined $test->{'env'})
        {
            for $key (keys %{$test->{'env'}})
            {
                $oldenv{$key} = $ENV{$key};
                $ENV{$key} = $test->{'env'}->{$key};
            }
        }
        #print "RUN: '$cmdtorun'\n";
        $output = `$cmdtorun`;
        $status = $?;
        #print "Status: $status\n";
        $test->{'duration'} = time() - $start_time;

        for $key (keys %{$test->{'env'}})
        {
            if (defined $oldenv{$key})
            {
                $ENV{$key} = $oldenv{$key};
            }
            else
            {
                delete $ENV{$key};
            }
        }
    }
    my $sig = ($status & 255);
    my $rc = $sig ? 128+$sig : ($status >> 8);
    if ($status == -1)
    {
        # File not found
        $sig = -1;
        $rc = 128;
        $output = "$cmdtorun could not be found";
    }

    my $fail = undef;
    if ($rc != $wantrc)
    {
        $fail = "Expected RC $wantrc, got $rc";
    }
    if (!$fail && defined $expect)
    {
        my $expected = read_file($expect, 'expect file');
        my $native_expect = native_filename($expect);

        # If they supplied replacements, see if we can apply them
        if ($replacements)
        {
            $output = apply_replacements($replacements, $output);
        }
        if ($output ne $expected)
        {
            $fail = "Expected output did not match";
            open(FH, "> $native_expect-actual") || die "Could not write expected output to '$native_expect-actual': $!";
            print FH $output;
            close(FH);
        }
        else
        {
            unlink "$native_expect-actual"
        }
    }
    if (!$fail && defined $removes)
    {
        if (-f $removes)
        {
            $fail = "Expected to remove $removes, but didn't";
        }
    }
    if (!$fail && defined $absent)
    {
        if (-f $absent)
        {
            $fail = "Expected to not create $absent, but the file exists";
        }
    }
    if (!$fail && defined $creates)
    {
        my @create_list = split / +/, $creates;
        for $created (@create_list)
        {
            $created = native_filename($created);
            if (!-e $created)
            {
                $fail = "Expected to create $created, but didn't";
            }
            elsif (defined $length)
            {
                # This only really works if there's a single file
                my $gotlength = -s $created;
                if ($gotlength != $length)
                {
                    $fail = "Expected output length $length, but got $gotlength";
                }
            }
        }

        if (!$fail)
        {
            for $checker (keys %checkers)
            {
                if (defined $test->{$checker})
                {
                    my %args = %{$test->{$checker}};
                    my $func = $checkers{$checker};
                    eval {
                        if ($creates =~ / /)
                        {
                            die "Cannot use checkers with multiple 'Creates'\n";
                        }
                        my $created = native_filename($creates);
                        for $key (keys %args)
                        {
                            $args{$key} = substitute($args{$key}, $vars);
                        }
                        $fail = & $func ($created, \%args);
                    };
                    if ($@)
                    {
                        $fail = "Exception: $@";
                        chomp $fail;
                    }
                    if ($fail)
                    {
                        $fail = "$checker: $fail";
                        last;
                    }
                }
            }
        }

        # Clear away the successfully created file.
        if (!$fail)
        {
            my @create_list = split / +/, $creates;
            for $created (@create_list)
            {
                $created = native_filename($created);
                unlink $created if (-f $created);
                rmdir $created if (-d $created);
            }
        }
    }
    if ($fail)
    {
        if ($sig)
        {
            print "${crash_colour}CRASH: $fail${reset_colour}\n";
            $test->{'result'} = 'crash';
        }
        else
        {
            print "${fail_colour}FAIL: $fail${reset_colour}\n";
            $test->{'result'} = 'fail';
        }
        $test->{'result_message'} = $fail;
        $test->{'result_output'} = $output;
    }
    else
    {
        print "${ok_colour}OK${reset_colour}\n";
        $test->{'result'} = 'pass';
    }
    if ($verbose)
    {
        $cmd =~ s/\Q$testtool/<$testtoolname>/g;
        if ($showcmd)
        {
            print "    $cmd\n";
        }
        if ($fail)
        {
            if ($outputdump)
            {
                print map { "    $_\n" } split /\n/, $output;
            }
        }
    }

    if ($outputsavedir)
    {
        my $dir = "$outputsavedir";
        mkdir "$dir", 0755;
        my $subdir = $test->{'group'};
        $subdir =~ s/ /-/g;
        $subdir =~ s/\//_/g;
        $dir = sprintf "%s/%03d_%s", $dir, $test->{'group-index'}, $subdir;
        mkdir "$dir", 0755;
        my $leaf = $name;
        $name =~ s/ /-/g;
        $name =~ s/\//_/g;
        my $path = sprintf "%s/%03d_%s.log", $dir, $test->{'test-index'}, $leaf;

        open(FH, "> $path") || die "Cannot open output save file '$path': $!";
        print FH $output;
        close(FH);
    }

    return 2 if ($sig);
    return $fail ? 1 : 0;
}


sub xml_escape
{
    my ($str) = @_;
    $str =~ s/&/&amp;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/>/&gt;/g;
    $str =~ s/'/&apos;/g;
    $str =~ s/"/&quot;/g;

    return $str;
}


sub write_junitxml
{
    my ($output, @groups) = @_;
    my $nerrors = 0;
    my $nfailures = 0;
    my $ntests = 0;
    my $nskipped = 0;

    my %result_tag_name = (
            'pass' => undef,
            'skip' => 'skipped',
            'fail' => 'failure',
            'crash' => 'error',
        );
    my %has_message = (
            'skip' => 0,
            'fail' => 1,
            'crash' => 1,
        );

    # sum the counts for the top level testsuite
    for $group (@groups)
    {
        $nerrors += $group->{'crash'};
        $nfailures += $group->{'fail'};
        $ntests += $group->{'pass'} + $nerrors + $nfailures;
        $nskipped += $group->{'skip'};
    }

    print "Writing JUnitXML file to '$output'\n";
    open(FH, "> $output") || die "Cannot write JunitXML '$output': $!";

    print FH "<?xml version=\"1.0\"?>\n";
    # FIXME: Should skipped be mapped to 'disabled' at the top level?
    print FH "<testsuites tests=\"$ntests\" failures=\"$nfailures\" errors=\"$nerrors\">\n";
    for $group (@groups)
    {
        $nerrors = $group->{'crash'};
        $nfailures = $group->{'fail'};
        $ntests = $group->{'pass'} + $nerrors + $nfailures;
        $nskipped = $group->{'skip'};
        my $duration = 0;
        for $test (@{ $group->{'tests'} })
        {
            next if (!defined $test->{'result'});
            if (defined $test->{'duration'})
            {
                $duration += $test->{'duration'};
            }
        }
        print FH "  <testsuite name=\"" . xml_escape($group->{'group'}) . "\" tests=\"$ntests\" failures=\"$nfailures\" errors=\"$nerrors\" skipped=\"$nskipped\"";
        if ($duration)
        {
            print FH sprintf " time=\"%.2f\"", $duration;
        }
        print FH ">\n";
        for $test (@{ $group->{'tests'} })
        {
            next if (!defined $test->{'result'});
            print FH "    <testcase classname=\"ToolTest\" name=\"" . xml_escape($test->{'name'}) . "\"";
            if (defined $test->{'duration'})
            {
                print FH sprintf " time=\"%.2f\"", $test->{'duration'};
            }
            if ($test->{'result'} eq 'pass')
            {
                print FH " />\n";
            }
            else
            {
                my $message = "$test->{'result'}: $test->{'result_message'}";
                print FH ">\n";
                my $tag = $result_tag_name{ $test->{'result'} };
                print FH "      <$tag";
                if ($has_message{ $test->{'result'} })
                {
                    print FH " message=\"$message\"";
                }
                print FH ">";
                my $output = $test->{'result_output'};
                if ($output)
                {
                    # Escape any ]]> that might confuse the CDATA
                    $output =~ s/]]>/]]]]><!\[CDATA\[>/g;
                    print FH "<![CDATA[${output}]]>\n";
                }
                print FH "      </$tag>\n";
                print FH "    </testcase>\n";
            }
        }
        print FH "  </testsuite>\n";
    }
    print FH "</testsuites>\n";
    close(FH);
}


#######################################################################

# General binary files (which may be extended by other users)

##
# Process a binary file
sub binaryfile
{
    my ($filename) = @_;
    my $bf = {
            'filesize' => -s $filename,
            'endian' => 'unknown',
        };
    local *BFH;
    open(BFH, "< $filename") || die "Cannot read chunk file '$filename'\n";
    my $bfd = {
            'fh' => \*BFH,
            'reverse' => 0,
        };

    $bf->{'bfd'} = $bfd;
    return $bf;
}


##
# Mark the binary file as little endian
sub binary_littleend
{
    my ($bf) = (@_);
    $bf->{'endian'} = 'little';
    $bf->{'bfd'}->{'reverse'} = 0;
}


##
# Mark the binary file as big endian
sub binary_bigend
{
    my ($bf) = @_;
    $bf->{'endian'} = 'big';
    $bf->{'bfd'}->{'reverse'} = 1;
}


##
# Read a 32bit word
sub readword
{
    my ($cfd) = @_;
    my $word;
    if (sysread($cfd->{'fh'}, $word, 4) != 4)
    {
        die "Short read of word at offset " . (sysseek($cfd->{'fh'}, 0, 1));
    }
    if ($cfd->{'reverse'})
    {
        $word = unpack 'N', $word;
    }
    else
    {
        $word = unpack 'V', $word;
    }
    if ($word < 0)
    {
        die "Read a negative word?!";
    }
    return $word;
}


##
# Read a 16bit word
sub readshort
{
    my ($cfd) = @_;
    my $word;
    if (sysread($cfd->{'fh'}, $word, 2) != 2)
    {
        die "Short read of short";
    }
    if ($cfd->{'reverse'})
    {
        $word = unpack 'n', $word;
    }
    else
    {
        $word = unpack 'v', $word;
    }
    if ($word < 0)
    {
        die "Read a negative short?!";
    }
    return $word;
}


##
# Read a byte
sub readbyte
{
    my ($cfd) = @_;
    my $word;
    if (sysread($cfd->{'fh'}, $word, 1) != 1)
    {
        die "Short read of byte";
    }
    $word = ord($word);
    if ($word < 0)
    {
        die "Read a negative short?!";
    }
    return $word;
}


##
# Read a fixed length string
sub readfixedstring
{
    my ($cfd, $len) = @_;
    my $str;
    sysread($cfd->{'fh'}, $str, $len);
    return $str;
}


#######################################################################

# Chunk file constants
my $ChunkFileId = 0xC3CBC6C5;
my $ChunkFileIdReverse = 0xC5C6CBC3;

# AOF Chunk file constants
my $aof_prefix = 'OBJ_';
my $aof_header = 'OBJ_HEAD';
my $aof_areas = 'OBJ_AREA';
my $aof_identification = 'OBJ_IDFN';
my $aof_symbols = 'OBJ_SYMT';
my $aof_strings = 'OBJ_STRT';

# ALF Chunk file constants
my $alf_prefix = 'LIB_';
my $alf_timestamp = 'LIB_TIME';
my $alf_version = 'LIB_VRSN';
my $alf_directory = 'LIB_DIRY';


##
# Process a chunk file
sub chunkfile
{
    my ($filename) = @_;
    my $cf = binaryfile($filename);
    my $cfd = $cf->{'bfd'};

    $cf->{'MaxChunks'} = 0;
    $cf->{'NumChunks'} = 0;
    $cf->{'chunks'} = [];
    $cf->{'chunknames'} = {};

    my $word = readword($cfd);
    if ($word == $ChunkFileId)
    {
        binary_littleend($cf);
    }
    elsif ($word == $ChunkFileIdReverse)
    {
        binary_bigend($cf);
    }

    $cf->{'MaxChunks'} = readword($cfd);
    $cf->{'NumChunks'} = readword($cfd);

    my $filesize = $cf->{'filesize'};

    for $n (0..$cf->{'MaxChunks'}-1)
    {
        my $chunkid = readfixedstring($cfd, 8);
        my $fileoffset = readword($cfd);
        my $size = readword($cfd);
        my $chunk_header = {
                'index' => $n,
                'chunkId' => $chunkid,
                'fileOffset' => $fileoffset,
                'size' => $size,
            };
        push @{$cf->{'chunks'}}, $chunk_header;
        $cf->{'chunknames'}->{$chunkid} = $chunk_header;

        if ($chunk_header->{'fileOffset'} > $filesize)
        {
            die "Chunk #$n starts at $chunk_header->{'fileOffset'}, which is > $filesize\n";
        }
        my $end = $chunk_header->{'fileOffset'} + $chunk_header->{'size'};
        if ($end > $filesize)
        {
            die "Chunk #$n end at $end, which is > $filesize\n";
        }
    }

    return $cf;
}


#######################################################################

# AOF-specific settings

# Attribute flags
my $aof_attribute_absolute = (1<<8);
my $aof_attribute_code = (1<<9);
my $aof_attribute_common = (1<<10);
my $aof_attribute_commonref = (1<<11);
my $aof_attribute_zeroinit = (1<<12);
my $aof_attribute_readonly = (1<<13);
my $aof_attribute_pic = (1<<14);
my $aof_attribute_debug = (1<<15);
my $aof_attribute_code_32bit = (1<<16);
my $aof_attribute_code_reentrant = (1<<17);
my $aof_attribute_code_fpe = (1<<18);
my $aof_attribute_code_swst = (1<<19);
my $aof_attribute_code_thumb = (1<<20);
my $aof_attribute_code_halfword = (1<<21);
my $aof_attribute_code_interworking = (1<<22);
my $aof_attribute_data_based = (1<<20);
my $aof_attribute_data_shared = (1<<21);
my $aof_attribute_data_sharedmask = (15<<24);
my $aof_attribute_data_sharedshift = (24);


sub aof_header
{
    my ($cf) = @_;
    my $cfd = $cf->{'bfd'};
    my $chunk = $cf->{'chunknames'}->{$aof_header};
    if (!defined $chunk)
    {
        return {};
    }
    seek($cfd->{'fh'}, $chunk->{'fileOffset'}, 0);

    $chunk->{'ObjectFileType'} = readword($cfd);
    $chunk->{'VersionId'} = readword($cfd);
    $chunk->{'NumberOfAreas'} = readword($cfd);
    $chunk->{'NumberOfSymbols'} = readword($cfd);
    $chunk->{'EntryAreaIndex'} = readword($cfd);
    $chunk->{'EntryAreaOffset'} = readword($cfd);
    $chunk->{'AreaHeaders'} = [];

    $chunk->{'totalAreaSize'} = 0;

    for $areanum (0..$chunk->{'NumberOfAreas'}-1)
    {
        # 5 words per area
        my $area = {
                'AreaNameSID' => readword($cfd),
                'Attributes' => readword($cfd),
                'AreaSize' => readword($cfd),
                'NumberOfRelocations' => readword($cfd),
                'BaseAddress' => readword($cfd),
            };
        push @{ $chunk->{'AreaHeaders'} }, $area;
        $area->{'Alignment'} = 1<<($area->{'Attributes'} & 255);

        if ($debug_aof) {
            print "AOFArea:\n";
            print map { "  $_: $area->{$_}\n" } ('AreaNameSID',
                                                 'Attributes',
                                                 'AreaSize',
                                                 'NumberOfRelocations',
                                                 'BaseAddress',
                                                 'Alignment');
        }

        $chunk->{'totalAreaSize'} += $area->{'AreaSize'};
    }

    return $chunk;
}

sub aof_strings
{
    my ($cf) = @_;
    my $cfd = $cf->{'bfd'};
    my $chunk = $cf->{'chunknames'}->{$aof_strings};
    if (!defined $chunk)
    {
        return {};
    }
    sysseek($cfd->{'fh'}, $chunk->{'fileOffset'}, 0);

    $chunk->{'tablelength'} = readword($cfd);
    sysseek($cfd->{'fh'}, $chunk->{'fileOffset'}, 0);
    $chunk->{'table'} = '';
    sysread($cfd->{'fh'}, $chunk->{'table'}, $chunk->{'tablelength'});

    return $chunk;
}

sub aof_identification
{
    my ($cf) = @_;
    my $cfd = $cf->{'bfd'};
    my $chunk = $cf->{'chunknames'}->{$aof_identification};
    if (!defined $chunk)
    {
        return {};
    }
    sysseek($cfd->{'fh'}, $chunk->{'fileOffset'}, 0);

    my $name = readfixedstring($cfd, $chunk->{'size'});
    $name =~ s/\0.*$//;
    $chunk->{'Identification'} = $name;

    return $chunk;
}

# Checking function

sub aof_check
{
    my ($filename, $args) = @_;

    my $cf = chunkfile($filename);
    my $header = aof_header($cf);

    # FIXME: Version check?

    my $areasize = $header->{'totalAreaSize'};
    if ($areasize % 4 != 0)
    {
        return "Total area size must be a multiple of 4, but got $areasize";
    }

    if (defined $args->{'totalareasize'} &&
        $args->{'totalareasize'} != $areasize)
    {
        return "Expected total area size $args->{'totalareasize'}, but got $areasize";
    }

    return undef;
}

#######################################################################

# ALF-specific settings

sub alf_directory
{
    my ($cf) = @_;
    my $cfd = $cf->{'bfd'};
    my $chunk = $cf->{'chunknames'}->{$alf_directory};
    if (!defined $chunk)
    {
        die "No ALF directory '$alf_directory' present in Chunk File\n";
    }
    sysseek($cfd->{'fh'}, $chunk->{'fileOffset'}, 0);

    $chunk->{'Directory'} = [];
    my $end = $chunk->{'fileOffset'} + $chunk->{'size'};
    while (sysseek($cfd->{'fh'}, 0, 1) < $end)
    {
        my $entry = {
                'ChunkIndex' => readword($cfd),
                'EntryLength' => readword($cfd),
                'DataLength' => readword($cfd),
            };
        if ($entry->{'EntryLength'} == 0)
        {
            die "EntryLength is stupid?"
        }
        $entry->{'Data'} = readfixedstring($cfd, $entry->{'DataLength'} - 8);
        my $name = "$entry->{'Data'}";
        $name =~ s/\0.*$//;
        $entry->{'Name'} = $name;
        $entry->{'TimeStampHi'} = readword($cfd);
        $entry->{'TimeStampLo'} = readword($cfd);
        push @{$chunk->{'Directory'}}, $entry;
    }

    return $chunk;
}

sub alf_timestamp
{
    my ($cf) = @_;
    my $cfd = $cf->{'bfd'};
    my $chunk = $cf->{'chunknames'}->{$alf_directory};
    if (!defined $chunk)
    {
        return {};
    }
    sysseek($cfd->{'fh'}, $chunk->{'fileOffset'}, 0);

    $chunk->{'TimeStampHi'} = readword($cfd);
    $chunk->{'TimeStampLo'} = readword($cfd);

    return $chunk;
}

sub alf_version
{
    my ($cf) = @_;
    my $cfd = $cf->{'bfd'};
    my $chunk = $cf->{'chunknames'}->{$alf_version};
    if (!defined $chunk)
    {
        return {};
    }
    sysseek($cfd->{'fh'}, $chunk->{'fileOffset'}, 0);

    if ($chunk->{'size'} != 4)
    {
        die "Version chunk is $chunk->{'size'} bytes, should be 4";
    }

    $chunk->{'Version'} = readword($cfd);

    return $chunk;
}

# Checking function

sub alf_check
{
    my ($filename, $args) = @_;

    my $cf = chunkfile($filename);
    my $dir = alf_directory($cf);

    my $version = alf_version($cf);
    if ($version->{"Version"} != 1)
    {
        die "Unrecognised ALF version: $version (only 1 supported)";
    }

    my $files = $dir->{'Directory'};
    my $nfiles = scalar(@$files);
    if ($args->{'files'} != $nfiles)
    {
        return "Expected $args->{'files'}, but got $nfiles";
    }

    return undef;
}


#######################################################################

# ELF-specific settings

sub elffile
{
    my ($filename) = @_;
    my $ef = binaryfile($filename);
    my $efd = $ef->{'bfd'};

    my $magic = readfixedstring($efd, 4);
    if ($magic ne "\x7fELF")
    {
        die "Bad magic string '$magic'";
    }
    my $class = readbyte($efd);
    if ($class != 1)
    {
        die "Bad class (should be 32 bit (1), not $class)";
    }
    my $endianness = readbyte($efd);
    if ($endianness != 1 && $endianness != 2)
    {
        die "Bad endianness (should be 1 or 2, not $endianness)";
    }
    my $elfversion = readbyte($efd);
    if ($elfversion != 1)
    {
        die "Bad ident version (should be 1, not $elfversion)";
    }

    $ef->{'OSABI'} = readbyte($efd);
    $ef->{'ABIVersion'} = readbyte($efd);
    $ef->{'Padding'} = readfixedstring($efd, 7);

    # From here on, the endianness matters
    if ($endianness == 1)
    {
        binary_littleend($ef);
    }
    else
    {
        binary_bigend($ef);
    }

    $ef->{'Type'} = readshort($efd);
    $ef->{'Machine'} = readshort($efd);
    $ef->{'Version'} = readword($efd);

    if ($ef->{'Version'} != 1)
    {
        die "Bad ELF version (should be 1, not $ef->{'Version'})";
    }
    $ef->{'Entry'} = readword($efd);
    $ef->{'PHOff'} = readword($efd);
    $ef->{'SHOff'} = readword($efd);
    $ef->{'Flags'} = readword($efd);
    $ef->{'EHSize'} = readshort($efd);
    $ef->{'PHEntSize'} = readshort($efd);
    $ef->{'PHNum'} = readshort($efd);
    $ef->{'SHEntSize'} = readshort($efd);
    $ef->{'SHNum'} = readshort($efd);
    $ef->{'SHStrNdx'} = readshort($efd);

    return $ef;
}


# Checking function

sub elf_check
{
    my ($filename, $args) = @_;
    my $ef = elffile($filename);

    if ($args->{'endianness'})
    {
        if ($ef->{'endian'} ne lc($args->{'endianness'}))
        {
            return "Expected endianness $args->{'endianness'}, but got $ef->{'endian'}";
        }
    }

    for $key ('Type', 'Entry', 'OSABI', 'PHOff', 'SHOff', 'EHSize', 'Flags',
              'PHEntSize', 'PHNum',
              'SHEntSize', 'SHNum', 'SHStrNdx')
    {
        my $argkey = lc($key);
        if (defined($args->{$argkey}) &&
            $ef->{$key} ne $args->{$argkey})
        {
            return "Expected $argkey $args->{$argkey}, but got $ef->{$key}";
        }
    }

    return undef;
}


#######################################################################

# Text-specific settings


# Checking function

sub text_check
{
    my ($filename, $args) = @_;

    my $txt = read_file($filename, 'generated text file');

    if ($args->{'replace'})
    {
        $txt = apply_replacements($args->{'replace'}, $txt);
    }
    if ($args->{'matches'})
    {
        my $expected = read_file($args->{'matches'}, 'expected text file');
        my $native_expect = native_filename($args->{'matches'});
        if ($txt ne $expected)
        {
            open(FH, "> $native_expect-actual")
                || die "Cannot write actual output content '$native_expect-actual': $!";
            print FH $txt;
            close(FH);
            return "Does not match expected text file (see $native_expect-actual)";
        }
        else
        {
            unlink "$native_expect-actual"
        }
    }

    return undef;
}

#######################################################################

# Binary-specific settings


sub binary_load
{
    my ($filename) = @_;
    my $bin = {
            'filename' => $filename,
            'data' => read_file($filename, 'generated binary file'),
            'size' => -s $filename,
        };

    return $bin;
}


##
# Read a word from the file
sub binary_word
{
    my ($bin, $offset) = @_;
    if ($offset + 4 > $bin->{'size'})
    {
        die "Word offset '$offset' is outside binary file (length $bin->{'size'})";
    }
    my $word = substr($bin->{'data'}, $offset, 4);
    my $value = unpack('V', $word);
    return $value;
}


##
# Read a byte from the file
sub binary_byte
{
    my ($bin, $offset) = @_;
    if ($offset + 4 > $bin->{'size'})
    {
        die "Byte offset '$offset' is outside binary file (length $bin->{'size'})";
    }
    my $word = substr($bin->{'data'}, $offset, 1);
    my $value = unpack('C', $word);
    return $value;
}


##
# Read a string from the file
sub binary_string
{
    my ($bin, $offset) = @_;
    if ($offset + 1 > $bin->{'size'})
    {
        die "String offset '$offset' is outside binary file (length $bin->{'size'})";
    }
    my $str = substr($bin->{'data'}, $offset);
    my $value = unpack('Z*', $str);
    return $value;
}


# Checking function

sub binary_check
{
    my ($filename, $args) = @_;

    my $bin = binary_load($filename);

    if ($args->{'checkfile'})
    {
        my $native_expect = native_filename($args->{'checkfile'});
        open(FH, "< $native_expect") || die "Cannot read binary check file '$native_expect': $!\n";
        my @fail;
        while (<FH>)
        {
            chomp;
            if (/^ *#/)
            {
                # Comment line
                next;
            }
            if (! s/^([0-9a-fx&]+) +//i)
            {
                die "Unrecognised offset in: '$_'\n";
            }
            my $offset = number($1);

            if (/word: (.*)$/i)
            {
                my $expect = $1;
                $expect = number($expect);
                my $value = binary_word($bin, $offset);
                if ($expect != $value)
                {
                    push @fail, sprintf "Word at offset 0x%x was 0x%08x, expected 0x%08x", $offset, $value, $expect;
                }
            }
            elsif (/byte: (.*)$/i)
            {
                my $expect = $1;
                $expect = number($expect);
                my $value = binary_byte($bin, $offset);
                if ($expect != $value)
                {
                    push @fail, sprintf "Byte at offset 0x%x was 0x%02x, expected 0x%02x", $offset, $value, $expect;
                }
            }
            elsif (/string: (.*)$/i)
            {
                my $expect = $1;
                my $value = binary_string($bin, $offset);
                if ($expect ne $value)
                {
                    push @fail, sprintf "String at offset 0x%x was '%s', expected '%s'", $offset, $value, $expect;
                }
            }
            else
            {
                die "Unrecognised binary checkfile directive: $_";
            }
        }
        close($fh);
        if (@fail)
        {
            my $number = scalar(@fail);
            if ($number > 1)
            {
                return "$number binary checks failed:\n" . join("\n", @fail);
            }
            return $fail[0];
        }
    }

    if ($args->{'matches'})
    {
        my $expected = read_file($args->{'matches'}, 'expected binary file');
        my $native_expect = native_filename($args->{'matches'});
        if ($bin->{'data'} ne $expected)
        {
            open(FH, "> $native_expect-actual")
                || die "Cannot write actual output content '$native_expect-actual': $!";
            print FH $bin->{'data'};
            close(FH);
            return "Does not match expected binary file (see $native_expect-actual)";
        }
        else
        {
            unlink "$native_expect-actual"
        }
    }

    return undef;
}


#######################################################################

# Actual tests

# Execute in the directory requested
# NOTE: On RISC OS, this is destructive, as there is only one CWD.
chdir "$dir";
my $filtereddir = $dir;
while ($filtereddir =~ s!\.\./[^./][^./][^/]+!!)
{} # Remove any ../<dir> components
my @dirparts = split m!/!, $filtereddir;
if (scalar(@dirparts) == 1 && $dir =~ /\./)
{
    # They gave a RISC OS path (FIXME: Decide how to convert the path above to native form)
    @dirparts = split m!\.!, $filtereddir;
}
# Strip the specifications of the current directory.
@dirparts = grep { $_ ne '@' && $_ ne '.' } @dirparts;


# Now build the relative location of the original directory
my $rootdir;
if ($^O eq 'riscos')
{
    $rootdir = '^.' x scalar(@dirparts);
    $rootdir = '@.' if ($rootdir eq '');
}
else
{
    $rootdir = '../' x scalar(@dirparts);
    $rootdir = './' if ($rootdir eq '');
}


# Ensure we output immediately, so that stderr appears in a sane place
$| = 1;

my @groups = parse_test_script($testscript);

my $pass = 0;
my $fail = 0;
my $crash = 0;
my $skip = 0;
for $group (@groups)
{
    if ($group->{'skip'})
    {
        # No need to mark individual tests; they will have been
        # flagged as skipped already.
        $group->{'skip'} = scalar(@{ $group->{'tests'} });
        $skip += $group->{'skip'};
        next;
    }
    print "$group->{'group'}:\n";
    $group->{'skip'} = 0;
    for $test (@{ $group->{'tests'} })
    {
        if ($test->{'skip'})
        {
            # The command line matching requested skipping
            $group->{'skip'}++;
            $test->{'result'} = 'skip';
            $skip++;
            next;
        }
        my $state = run_test($test);
        if ($state == 0)
        {
            $group->{'pass'}++;
            $pass++;
        }
        elsif ($state == 1)
        {
            $group->{'fail'}++;
            $fail++;
        }
        elsif ($state == 2)
        {
            $group->{'crash'}++;
            $crash++;
        }
        elsif ($state == -1)
        {
            $group->{'skip'}++;
            $skip++;
        }
    }
}

print "\n";
print "-----------\n";
printf "Pass:  %6d\n", $pass;
printf "Fail:  %6d\n", $fail;
printf "Crash: %6d\n", $crash;
printf "Skip:  %6d\n", $skip;
print "-----------\n";
my $total = $pass + $fail + $crash;
printf "Total run:   %6d\n", $total;
if ($total != 0)
{
    printf "Pass ratio:  %6.2f %%\n", 100 * $pass / $total;
    printf "Fail ratio:  %6.2f %%\n", 100 * $fail / $total;
    if ($crash)
    {
        printf "Crash ratio: %6.2f %%\n", 100 * $crash / $total;
    }
}

if ($junitxml)
{
    # Turn the junitxml into a native path
    $junitxml = native_filename($junitxml);
    if ($junitxml =~ m!^/! || $junitxml =~ m![\$@%]!)
    {
        # Already anchored.
    }
    else
    {
        $junitxml = $rootdir . $junitxml;
    }
    write_junitxml($junitxml, @groups);
}

exit(($fail+$crash) == 0 ? 0 : 1);
