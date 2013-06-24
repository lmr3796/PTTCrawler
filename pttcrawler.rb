#! /usr/bin/env ruby
# encoding: UTF-8

#
# Copyright (c) 2013, Tingchou Lin
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification, are permitted provided that the
# following conditions are met:
#
#   * The copy is for non-commercial use or commercial use granted by the owner.
#
#   * Redistributions of source code must retain the above copyright notice, this list of conditions and the
#     following disclaimer.
#
#   * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the
#     following disclaimer in the documentation and/or other materials provided with the distribution.
#
#   * Neither the name of the NTU nor the names of its contributors may be used to endorse or promote
#     products derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
# INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
# USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

require 'net/telnet'

CONTROL_CODE_REGEX = Regexp.compile('\x1B\[(?:(?>(?>(?>\d+;)*\d+)?)m|(?>(?>\d+;\d+)?)H|K)'.force_encoding('binary'), Regexp::FIXEDENCODING)
class Canvas
  def error_buf
    @error_buf
  end
  def cursor
    @cursor
  end
  def screen
    @screen
  end

  # By default an ANSI 80 * 24 Terminal
  def initialize(max_col=80, max_row=24)
    @max_row = max_row
    @max_col = max_col
    clear
  end

  def clear
    @cursor = {:row => 0, :col => 0}
    @screen = []
    for i in 0...@max_row
      @screen << ' '*@max_col
    end
  end

  def update(buf)
    while buf.size > 0
      next_control_id = buf.index(CONTROL_CODE_REGEX)
      if next_control_id == 0
        #Process it only if it's cursor control sequence
        control = buf.slice!(CONTROL_CODE_REGEX)
        case control
        when /\e\[((?<row>\d{1,2});(?<col>\d{1,2}))?(H|f)/
          dump_screen control
          @cursor[:row] = ($~[:row] || 1).to_i - 1
          @cursor[:col] = ($~[:col] || 1).to_i - 1
        when /\e\[(?<type>)K/
          type = $~[:type]
          range = case type
                  when ''
                    # <ESC>[K  ==> Current to end
                    @cursor[:col]...@max_col
                  when 1
                    # <ESC>[1K ==> Head to current
                    0..@cursor[:col]
                  when 2
                    # <ESC>[2K ==> Full line
                    0...@max_col
                  else
                  end
          erase_range(range)
        end
      else
        # If no more control code then slice all!!
        @raw_str = buf.slice!(0...next_control_id) rescue buf.slice!(0..-1)
        write_raw_str(@raw_str)
      end
    end
  end

  def erase_range(range)
    range.each{|i| @screen[@cursor[:row]][i] = ' '}
    @cursor[:col] = range.max
  end

  def dump_screen(control='', to_stderr=false)
    if to_stderr
      bar = '=' * ((@max_col - control.size)/2)
      bar = "\t#{bar}#{control}#{bar}"
      $stderr.puts bar
      @screen.each_with_index{|s, index|
        line = s.encode('utf-8','big5',{:invalid => :replace, :undef => :replace, :replace =>' '})
        $stderr.puts "#{index}:#{s.size}\t|#{line}|"
      }
    end
    return @screen.map{|s| s.encode('utf-8','big5',{:invalid => :replace, :undef => :replace, :replace =>' '})}
  end

  def write_raw_str(str)
    # Must simulate 1 by 1 because we have no idea about when will a new line appear...
    str.each_char{|c|
      dump_screen
      new_line_cursor = lambda {
        @cursor[:col] = 0
        if @cursor[:row] + 1 < @max_row
          @cursor[:row] += 1
        else 
          # Overflow
          @screen.delete_at(0)
          @screen << (' '*@max_col)
        end
      }
      case c
      when "\b"
        erase_range(@cursor[:col]-1...@cursor[:col])
      when "\n"
        new_line_cursor.call
      when /\r/
        next
      else
        # Can't check new line after, otherwise a \n after a full line will cause a redundant line
        new_line_cursor.call if @cursor[:col] == @max_col
        @screen[@cursor[:row]][@cursor[:col]] = c
        @cursor[:col] += c.size
      end
    }
  end
end

class Crawler
  @@KEY = {
    :up     => "\e[A",
    :down   => "\e[B",
    :left   => "\e[D",
    :right  => "\e[C",
    :pgup   => "\e[5~",
    :pgdn   => "\e[6~",
    :home   => "\e[1~",
    :end    => "\e[4~",
  }

  def session
    @tn
  end
  def self.KEY
    @@KEY
  end


  def initialize(opt)
    @tn = Net::Telnet.new(
      'Host'    => opt[:host],
      'Timeout'   => 2,
      'Waittime'  => 3,
    )
    ObjectSpace.define_finalizer(self, proc{@tn.close()})
    @username = opt[:username]
    @password = opt[:password]
    @canvas = Canvas.new
  end

  def dump_screen(control='', to_stderr=false)
    @canvas.dump_screen(control, to_stderr)
  end

  def login
    $stderr.puts 'Login...'
    @tn.waitfor(/guest/)
    @tn.puts('')
    @tn.cmd('Match' => /./, 'String' => "#{@username}\r#{@password}\r")

    # Log out other connections, remove failure log...
    for i in 0...2
        begin
            @tn.waitfor('Match' => /\[Y\/n\]/, 'Waittime' => 2, 'String' => '')
            @tn.puts('n')  
        rescue
            break
        end
    end
    @tn.cmd('Match' => Regexp.new("批踢踢實業坊".encode('big5').force_encoding('binary')), 'String' => @@KEY[:left])
  end

  def send_cmd(c, opt={})
    binmode_tmp = @tn.binmode   # In order to store the state back
    # Must set this to switch off the implicit "enter" on every key stroke, 
    @tn.binmode = (opt[:enter] == true ? false : true)
    if opt[:update]
      @canvas.update(@tn.cmd('Match' => opt[:match] || /./, 'String' => c))
    else
      @tn.cmd('Match' => opt[:match] || /./, 'String' => c)
    end
    @tn.binmode = binmode_tmp
  end

  def goto_board(board_name)
    $stderr.puts "Going to board #{board_name}..."
    @tn.puts("s#{board_name}")
    begin
      @tn.waitfor('Match' => Regexp.new("看板《".encode('big5').force_encoding('binary')))
    rescue
      @tn.puts('')
      retry
    end
  end

  # Get the article that PTT cursor currently at
  def fetch_current_article()
    # Enter the article and start reading to the buf
    result = []
    get_line_range = lambda{
      from = @canvas.dump_screen[23].index('~')+1
      to = @canvas.dump_screen[23].index('行')
      return @canvas.dump_screen[23][from..to].to_i
    }
    # TODO: detect 本文已被刪除 so that left after going into article can be done here
    send_cmd(@@KEY[:right], :update => true)
    result.concat(@canvas.dump_screen[0...-2])    # The last line was simply a status bar, ignore it
    last_range = get_line_range.call
    while true  # Greedily read until no more data and handled by the rescue
      send_cmd(@@KEY[:pgdn], :update => true)
      curr_range = get_line_range.call
      result.concat(@canvas.dump_screen[-(curr_range - last_range + 1)..-2])
      last_range = curr_range
      return result if @canvas.dump_screen[23].include?'100%'
    end
  end

  def search_article_by_id(article_id, board_name)
    # Goto the board
    goto_board(board_name) if board_name

    # Goto a certain article
    @tn.cmd('Match' => /./, 'String' => article_id)
    return fetch_current_article
  end

end


# main body if used as a executable
# Here are sample usages
if __FILE__ ==  $PROGRAM_NAME
  PUSH_CONSTRAINT = 20
  BOARD_NAME = 'pc_shopping'
  crawler = Crawler.new(:host => 'ptt.cc', :username => ARGV[0], :password => ARGV[1])
  crawler.login
  crawler.goto_board BOARD_NAME
  crawler.send_cmd("Z#{PUSH_CONSTRAINT}", :enter => true)
  crawler.send_cmd('/[請益]'.encode('big5').force_encoding('binary'), :enter => true, :update=>true)
  #puts '/[請益]'.encode('big5').force_encoding('binary')
  #crawler.search_article_by_id('#1HmhiC9D', 'gossiping')
  for i in 1..30
    article_file_name = "#{BOARD_NAME}#{i}"
    $stderr.write "Fetching #{article_file_name}...."
    article = crawler.fetch_current_article
    if article.size > 10
      crawler.send_cmd(Crawler.KEY[:left])
      crawler.send_cmd(Crawler.KEY[:up])
      $stderr.puts "done."
      push_index = article.find_index{|s| s =~ /^※ 發信站: 批踢踢實業坊\(ptt\.cc\)/}
      begin
        open("#{article_file_name}.txt", 'w'){|f| f.puts article[0...push_index]}
        open("#{article_file_name}.push", 'w'){|f| f.puts article[(push_index+2)..-1]}
      rescue
        $stderr.puts 'Separating comments failed'
        open("#{article_file_name}.txt", 'w'){|f| f.puts article}
      end
    else
      crawler.send_cmd(Crawler.KEY[:up])
      $stderr.puts "seems to be a useless article"
      redo
    end
  end
end
