#! /usr/bin/env ruby
# encoding: UTF-8


require 'net/telnet'

class PTTCrawler
    def initialize(opt)
        @tn = Net::Telnet.new(
            'Host'    => opt[:host],
            'Timeout'   => 3,
            'Waittime'  => 2,
        )
        @username = opt[:username]
        @password = opt[:password]
    end
    def login
        @tn.waitfor(/guest/)
        @tn.puts('')
        @tn.cmd('Match' => /./, 'String' => "#{@username},\r#{@password}\r"){|s| puts s}

        # Log out other connections, remove failure log...
        for i in 0...2
        begin
            @tn.waitfor('Match' => /\[Y\/n\]/, 'Waittime' => 5, 'String' => ''){|s| @tn.puts('n'); puts s}  
        rescue
            break
        end
        end
        @tn.cmd('Match' => Regexp.new("批踢踢實業坊".force_encoding('binary')), 'String' => ''){|s| puts s}
    end
end


crawler = PTTCrawler.new(:host => 'ptt.cc', :username => argv[1], :password => argv[2])
crawler.login



