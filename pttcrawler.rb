#! /usr/bin/env ruby
# encoding: UTF-8


require 'net/telnet'

class Article
end
class PTTCrawler
    @@refresh = '^L'
    @@key = {
        :up     => "\e[A",
        :down   => "\e[B",
        :left   => "\e[D",
        :right  => "\e[C",
        :pgup   => "\e[5~",
        :pgdn   => "\e[6~",
        :home   => "\e[1~",
        :end    => "\e[4~",
    }
    def initialize(opt)
        @tn = Net::Telnet.new(
            'Host'    => opt[:host],
            'Timeout'   => 2,
            'Waittime'  => 0.3,
        )
        ObjectSpace.define_finalizer(self, proc{@tn.close()})
        @username = opt[:username]
        @password = opt[:password]
        login()
    end
    def login
        @tn.waitfor(/guest/)
        @tn.puts('')
        @tn.cmd('Match' => /./, 'String' => "#{@username},\r#{@password}\r")#{|s| puts s}

        # Log out other connections, remove failure log...
        for i in 0...2
            begin
                @tn.waitfor('Match' => /\[Y\/n\]/, 'Waittime' => 5, 'String' => '')#{|s| @tn.puts('n'); puts s}  
            rescue
                break
            end
        end
        @tn.cmd('Match' => Regexp.new("批踢踢實業坊".force_encoding('binary')), 'String' => '')#{|s| puts s}
    end
    def goto_board(board_name)
        @tn.puts("s#{board_name}")
        begin
            @tn.waitfor('Match' => Regexp.new("看板《".force_encoding('binary')))#{|s| puts s}
        rescue
            @tn.puts('')
            retry
        end
    end
    def search_article_by_id(article_id, board_name)
        # Goto the board
        goto_board(board_name) if board_name

        # Goto a certain article
        @tn.cmd('Match' => /./, 'String' => article_id)

        binmode_tmp = @tn.binmode   # In order to store the state back

        # Must set this to switch off the implicit "enter" on every key stroke, 
        @tn.binmode = true

        # Enter the article and start reading to the buf
        buf = @tn.cmd('Match' => /./, 'Waittime' => 1, 'String' => @@key[:right]){|s| $stderr.print(s)}
        while true  # Greedily read until no more data and handled by the rescue
            buf += @tn.cmd('Match' => /./, 'Waittime' => 1, 'String' => @@key[:pgdn]){|s| $stderr.print(s)}
        end
    rescue
        @tn.binmode = binmode_tmp
        return buf
    end
end


crawler = PTTCrawler.new(:host => 'ptt.cc', :username => ARGV[0], :password => ARGV[1])
puts crawler.search_article_by_id('#1Hl8-Aly', 'gossiping')
#s = open('log').read
#
#pattern = "瀏覽 第 1/10 頁 (  4%).*離開"
#print s =~ Regexp.new(pattern.force_encoding('binary'))




