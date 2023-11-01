#!/usr/bin/perl

use strict;
use warnings;

my $conf_file = '/var/lib/vz/snippets/virtiofs_hook.conf';
my %associations;

open my $cfg, '<', $conf_file or die "Failed to open virtiofs_hook.conf";
while (my $line = <$cfg>) {
    chomp $line;
    my ($vm_id, $paths_str) = split /:/, $line;
    my @path = split /,/, $paths_str;
    $associations{$vm_id} = \@path;
}

close $cfg or warn "Close virtiofs_hook.conf failed: $!";

use PVE::QemuServer;

use Template;
my $tt = Template->new;

print "GUEST HOOK: " . join(' ', @ARGV) . "\n";

my $vmid = shift;
my $conf = PVE::QemuConfig->load_config($vmid);
my $vfs_args_file = "/run/$vmid.virtfs";
my $virtiofsd_dir = "/run/virtiofsd/";
my $DEBUG = 1;
my $phase = shift;

my $unit_tpl = "[Unit]
Description=virtiofsd filesystem share at [% share %] for VM %i
StopWhenUnneeded=true

[Service]
Type=simple
RuntimeDirectory=virtiofsd
PIDFile=/run/virtiofsd/.run.virtiofsd.%i-[% share_id %].sock.pid
ExecStart=/usr/libexec/virtiofsd --log-level debug --socket-path /run/virtiofsd/%i-[% share_id %].sock --shared-dir [% share %] --cache=auto --announce-submounts --inode-file-handles=mandatory

[Install]
RequiredBy=%i.scope\n";

if ($phase eq 'pre-start') {
  print "$vmid is starting, doing preparations.\n";

  my $vfs_args = "-object memory-backend-memfd,id=mem,size=$conf->{memory}M,share=on -numa node,memdev=mem";
  my $char_id = 0;

  # Create the virtiofsd directory if it doesn't exist
  if (not -d $virtiofsd_dir) {
     print "Creating directory: $virtiofsd_dir\n";
     mkdir $virtiofsd_dir or die "Failed to create $virtiofsd_dir: $!";
    }

  # TODO: Have removal logic. Probably need to glob the systemd directory for matching files.
  for (@{$associations{$vmid}}) {
    # my $share_id = $_ =~ s/^\///r =~ s/\//_/gr;
    my $share_id = $_ =~ m/.*\/([^\/]+)/ ? $1 : '';  # only last folder from path
    my $unit_name = 'virtiofsd-' . $vmid . '-' . $share_id;
    my $unit_file = '/etc/systemd/system/' . $unit_name . '@.service';
    print "attempting to install unit $unit_name...\n";
    if (not -d $virtiofsd_dir) {
        print "ERROR: $virtiofsd_dir does not exist!\n";
    }
    else { print "DIRECTORY DOES EXIST!\n"; }

    if (not -e $unit_file) {
      $tt->process(\$unit_tpl, { share => $_, share_id => $share_id }, $unit_file)
        || die $tt->error(), "\n";
      system("/usr/bin/systemctl daemon-reload");
      system("/usr/bin/systemctl enable $unit_name\@$vmid.service");
    }
    system("/usr/bin/systemctl start $unit_name\@$vmid.service");
    $vfs_args .= " -chardev socket,id=char$char_id,path=/run/virtiofsd/$vmid-$share_id.sock";
    $vfs_args .= " -device vhost-user-fs-pci,chardev=char$char_id,tag=$vmid-$share_id";
    $char_id += 1;
  }

  open(FH, '>', $vfs_args_file) or die $!;
  print FH $vfs_args;
  close(FH);

  print $vfs_args . "\n";
  if (defined($conf->{args}) && not $conf->{args} =~ /$vfs_args/) {
    print "Appending virtiofs arguments to VM args.\n";
    $conf->{args} .= " $vfs_args";
  } else {
    print "Setting VM args to generated virtiofs arguments.\n";
    print "vfs_args: $vfs_args\n" if $DEBUG;
    $conf->{args} = " $vfs_args";
  }
  PVE::QemuConfig->write_config($vmid, $conf);
}
elsif($phase eq 'post-start') {
  print "$vmid started successfully.\n";
  my $vfs_args = do {
    local $/ = undef;
    open my $fh, "<", $vfs_args_file or die $!;
    <$fh>;
  };

  if ($conf->{args} =~ /$vfs_args/) {
    print "Removing virtiofs arguments from VM args.\n";
    print "conf->args = $conf->{args}\n" if $DEBUG;
    print "vfs_args = $vfs_args\n" if $DEBUG;
    $conf->{args} =~ s/\ *$vfs_args//g;
    print $conf->{args};
    $conf->{args} = undef if $conf->{args} =~ /^$/;
    print "conf->args = $conf->{args}\n" if $DEBUG;
    PVE::QemuConfig->write_config($vmid, $conf) if defined($conf->{args});
  }
}
elsif($phase eq 'pre-stop') {
  #print "$vmid will be stopped.\n";
}
elsif($phase eq 'post-stop') {
  #print "$vmid stopped. Doing cleanup.\n";
} else {
  die "got unknown phase '$phase'\n";
}

exit(0);
