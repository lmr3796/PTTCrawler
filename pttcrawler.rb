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
    def goto_board(board_name)
        @tn.puts("s#{board_name}")
        begin
            @tn.waitfor('Match' => Regexp.new("看板《".force_encoding('binary'))){|s| puts s}
        rescue
            @tn.puts('')
            retry
        end
    end
end


crawler = PTTCrawler.new(:host => 'ptt.cc', :username => ARGV[0], :password => ARGV[1])
crawler.login
crawler.goto_board('gossiping')



