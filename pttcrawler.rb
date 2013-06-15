#! /usr/bin/env ruby
# encoding: UTF-8


require 'net/telnet'

class Article
end
class PTTCrawler
    @@refresh = '^L'
    @@arrow = {
        :up => '^[[A',
        :down => '^[[B',
        :left => '^[[D',
        :right => '^[[C',
    }
    def initialize(opt)
        @tn = Net::Telnet.new(
            'Host'    => opt[:host],
            'Timeout'   => 3,
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
        goto_board(board_name) if board_name
        @tn.cmd('Match' => /./, 'String' => article_id)#{|s| print(s)}
        @tn.cmd('Match' => /./, 'String' => @@arrow[:right])#{|s| print(s)}
    end
    def read_terminal()
        return @tn.cmd('Match' => /./, 'String' =>@@refresh)
    end
end


crawler = PTTCrawler.new(:host => 'ptt.cc', :username => ARGV[0], :password => ARGV[1])
crawler.search_article_by_id('#1Hl8-Aly', 'gossiping')
puts crawler.read_terminal




