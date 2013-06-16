#! /usr/bin/env ruby
# encoding: UTF-8


require 'net/telnet'

CONTROL_CODE_REGEX = Regexp.compile(/\x1B\[(?:(?>(?>(?>\d+;)*\d+)?)m|(?>(?>\d+;\d+)?)H|K)/)
class Canvas
  def initialize(max_col=80, max_row=24)
    # ANSI 80 * 24 Terminal
    @max_row = max_row
    @max_col = max_col
    @screen = [' ' * @max_col] * @max_row # A continuous buffer to simulate it....
    @cursor = {:row => 0, :col => 0}
  end

  def update(buf)
    while buf.size > 0
      next_control_id = buf.index(CONTROL_CODE_REGEX)
      if next_control_id == 0
        #Process it only if it's cursor control sequence
        control = buf.slice!(CONTROL_CODE_REGEX)
        case control
        when /\e\[((?<row>\d{1,2});(?<col>\d{1,2}))?(H|f)/
          $stderr.puts 'Cursor control!'
          @cursor[:row] = $1[:row] or 0
          @cursor[:col] = $1[:col] or 0
        when /\e\[(?<type>)K/
          $stderr.puts 'Erase control!'
          range = case $1[:type]
                  when nil
                    # <ESC>[K  ==> Current to end
                    @cursor..@max_col
                  when 1
                    # <ESC>[1K ==> Head to current
                    0...@cursor
                  when 2
                    # <ESC>[2K ==> Full line
                    0..@max_col
                  end
          range.each{|i| @screen[@cursor[:row]][i] = ' '}
          @cursor[:row] = range.max
        end
      else
        write_raw_str(buf.slice!(0...next_control_id))
      end
    end
  end


  def write_raw_str(str)
    # Must simulate 1 by 1 because we have no idea about when will a new line appear...
    str.each_char{|c|
      new_line_cursor = lambda {
        @cursor[:col] = 0
        if @cursor[:row] +1 < @max_row
          @cursor[:row] += 1
        else 
          # Overflow
          @screen.delete_at(0)
          @screen.push(' '*@max_col)
        end
      }
      case c
      when '\r'
        next
      when '\n'
        new_line_cursor.call
      else
        @screen[@cursor[:row]][@cursor[:col]] = c
        @cursor[:col] += 1
        new_line_cursor.call if @cursor[:col] == @max_col
      end
    }
  end

  def cursor
    @cursor
  end
  def screen
    @screen
  end
end

class Crawler
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
    @canvas = Canvas.new
    login()
  end
  def login
    @tn.waitfor(/guest/)
    @tn.puts('')
    @tn.cmd('Match' => /./, 'String' => "#{@username}\r#{@password}\r")#{|s| puts s}

    # Log out other connections, remove failure log...
    #for i in 0...2
    #    begin
    #        @tn.waitfor('Match' => /\[Y\/n\]/, 'Waittime' => 5, 'String' => ''){|s| @tn.puts('n'); puts s}  
    #    rescue
    #        break
    #    end
    #end
    @tn.cmd('Match' => Regexp.new("批踢踢實業坊".encode('big5').force_encoding('binary')), 'String' => @@key[:left])#{|s| puts s}
  end
  def goto_board(board_name)
    @tn.puts("s#{board_name}")
    begin
      @tn.waitfor('Match' => Regexp.new("看板《".encode('big5').force_encoding('binary')))#{|s| puts s}
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
    result = ''
    buf = @tn.cmd('Match' => /./, 'Waittime' => 1, 'String' => @@key[:right])#{|s| $stderr.print(s)}
    result += preprocess_pgdn(buf)
    while true  # Greedily read until no more data and handled by the rescue
      buf = @tn.cmd('Match' => /./, 'Waittime' => 1, 'String' => @@key[:pgdn])#{|s| $stderr.print(s)}
      result += preprocess_pgdn(buf)
    end
  rescue TimeoutError
    @tn.binmode = binmode_tmp
    return result
    #return gsub_ansi_by_space(result)
  end

  def preprocess_pgdn(buf)
    #@canvas.write_buf(buf)
    #pattern = "瀏覽 第.*頁 (.*%).*離開"
    #buf.gsub!(/#{pattern.force_encoding('binary')}/, '')
    #buf.gsub!(/(^\s*)|\x08|\r/, '')
    ## Cursor moving
    #buf.gsub!(/\x1B\[\d{1,2};\d{1,2}H/,"\n")
    ## color code
    #buf.gsub!(/\x1B\[((\d{1,2};)*\d{1,2})?m/,'')
    ##buf.gsub!(/\x1B\[K/, '')
    return buf
  end

  # Copied from http://godspeedlee.myweb.hinet.net/ruby/ptt2.htm
  def gsub_ansi_by_space(s)
    raise ArgumentError, "search_by_title() invalid title:" unless s.kind_of? String
    s.gsub!(/\x1B\[(?:(?>(?>(?>\d+;)*\d+)?)m|(?>(?>\d+;\d+)?)H|K)/) do |m|
      if m[m.size-1].chr == 'K'
        "\n"
      else
        " "
      end
    end
  end 
end


# main body if used as a executable
if __FILE__ ==  $PROGRAM_NAME
  #crawler = Crawler.new(:host => 'ptt.cc', :username => ARGV[0], :password => ARGV[1])
  #puts crawler.search_article_by_id('#1Hl8-Aly', 'gossiping').split('\r')

  #s = open('article.log').readlines
  #s.each_with_index{|val, index|
  #    puts index if val.force_encoding('binary') =~ Regexp.new(pattern.force_encoding('binary'))
  #}
end
