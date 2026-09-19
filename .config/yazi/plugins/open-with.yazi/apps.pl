#!/usr/bin/perl
use strict;
use warnings;
use Encode qw(decode);
use Encode::Locale;
use Cwd qw(abs_path);
use File::Spec;
use File::MimeInfo::Magic qw(mimetype);
use File::MimeInfo::Applications qw(mime_applications_all);
use File::DesktopEntry;
use JSON::PP;

# Match mimeopen's filename decoding, MIME detection, ordering and deduplication.
@ARGV = map { my $s = eval { decode(locale => $_, 1) }; defined $s ? $s : $_ } @ARGV;
binmode STDOUT, ':raw';
binmode STDERR, ':encoding(UTF-8)';

my $mode = shift @ARGV // '';
if ($mode eq 'list') {
    @ARGV == 1 or die "Usage: apps.pl list FILE\n";
    my $file = $ARGV[0];
    -e $file or die "File no longer exists: $file\n";
    my $target = -l $file ? abs_path($file) : $file;
    my $mime = mimetype($target);
    defined($mime) && length($mime) or die "Could not determine this file's type.\n";

    my (@apps, %seen);
    for my $app (grep defined, mime_applications_all($mime)) {
        my (undef, undef, $id) = File::Spec->splitpath($app->{file});
        $id =~ s/\.desktop$//;
        next if $seen{$id}++;
        push @apps, {
            id      => $id,
            name    => $app->get_value('Name') // $id,
            desktop => $app->{file},
        };
    }
    print JSON::PP->new->utf8->encode({ mime => $mime, apps => \@apps });
}
elsif ($mode eq 'launch') {
    @ARGV == 2 or die "Usage: apps.pl launch DESKTOP_FILE FILE\n";
    my ($desktop, $file) = @ARGV;
    -f $desktop && -r $desktop or die "Application entry is no longer available: $desktop\n";
    -e $file or die "File no longer exists: $file\n";
    # Handles desktop-entry quoting, %f/%F/%u/%U, Path and Terminal exactly as
    # mimeopen does. No shell parsing of filenames or Exec values is introduced.
    File::DesktopEntry->new($desktop)->exec($file);
}
else {
    die "Usage: apps.pl {list FILE | launch DESKTOP_FILE FILE}\n";
}
