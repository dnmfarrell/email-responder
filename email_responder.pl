#!/usr/bin/env perl

use 5.10.3;
use warnings;
use Mail::POP3Client;
use Net::SMTP::SSL;
use YAML 'LoadFile';
use List::MoreUtils 'any';
use Authen::SASL;

my $config = LoadFile('config.yml') or die $!;
my %reply_emails = ();

read_emails();
send_replies();

sub read_emails
{
    open my $uid_log, '<', $config->{options}{uidl_log} or die "Error reading log file $config->{uidl_log} $!";
    my @uidls_already_responded = <$uid_log>;

    my $pop3 = new Mail::POP3Client(
            USER            => $config->{options}{pop3_user},
            PASSWORD        => $config->{options}{pop3_pass},
            HOST            => $config->{options}{pop3_host},
            PORT            => $config->{options}{pop3_port},
            USESSL          => $config->{options}{pop3_ssl},
    );

    for my $num (1..$pop3->Count)
    {
        # skip if we've already seen the msg before
        my $uidl = $pop3->Uidl($num);
        next if any { /^$uidl$/ } @uidls_already_responded;
        {
            for ($pop3->Head($num))
            {
                # get the senders email address
                if (/^From:.*?<(.*?)>$/i)
                {
                    $reply_emails{$uidl} = $1;
                }
                elsif (/^From:\s+(.*?)$/i)
                {
                    $reply_emails{$uidl} = $1;
                }
            }
        }
    }
    $pop3->Close();
}

sub send_replies {

    # the email responses will be randomly picked from config.yaml
    my @subjects = @{$config->{subjects}};
    my @messages = @{$config->{messages}};

    say "Sending reply emails";
    $smtp = Net::SMTP::SSL->new(
                    Host    => $config->{options}{smtp_host},
                    Port    => $config->{options}{smtp_port},
                    Timeout => 30,
            );

    # try to login
    if ($smtp->auth($config->{options}{smtp_user},
                    $config->{options}{smtp_pass}))
    {
        for my $reply_email (values %reply_emails)
        {
            my $subject = $subjects[int rand @subjects];
            my $message = $messages[int rand @messages];

            $smtp->mail($config->{options}{smtp_user});
            $smtp->to($reply_email);
            $smtp->data();
            my $email = ["To: <$reply_email>\n",
                         "From: <$config->{options}{smtp_user}>\n",
                         "Content-Type: text/html\n",
                         "Subject: " . $subject . "\n",
                         $message];
            $smtp->datasend($email);
            $smtp->dataend();
        }
        $smtp->quit();

        # write email unique ids to log
        open my $log, '>>', $config->{options}{uidl_log} or die $!;
        for my $uidl (keys %reply_emails)
        {
            print $log $uidl;
        }
    }
    else
    {
        die "invalid username / password";
    }
}

