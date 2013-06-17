#! /usr/bin/env ruby
# encoding: UTF-8


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
          @cursor[:row] = ($~[:row] or 1).to_i - 1
          @cursor[:col] = ($~[:col] or 1).to_i - 1
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
        @screen[@cursor[:row]][@cursor[:col]] = c
        @cursor[:col] += c.size
        new_line_cursor.call if @cursor[:col] == @max_col
      end
    }
  end
end

class Crawler
  @@refresh = "^L"
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

  def session
    @tn
  end

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
  end

  def dump_screen
    @canvas.dump_screen
  end

  def login
    @tn.waitfor(/guest/)
    @tn.puts('')
    @tn.cmd('Match' => /./, 'String' => "#{@username}\r#{@password}\r")#{|s| puts s}

    # Log out other connections, remove failure log...
    for i in 0...2
        begin
            @tn.waitfor('Match' => /\[Y\/n\]/, 'Waittime' => 5, 'String' => '')
            @tn.puts('n')  
        rescue
            break
        end
    end
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
    result = []
    @canvas.update(@tn.cmd('Match' => /./, 'Waittime' => 2, 'String' => @@key[:right]))
    result.concat(@canvas.dump_screen) 
    while true  # Greedily read until no more data and handled by the rescue
      @canvas.update(@tn.cmd('Match' => /./, 'Waittime' => 2, 'String' => @@key[:pgdn]))
      result.concat(@canvas.dump_screen[1...-1])  #Page down duplicates last line at line 1, so ignore it
    end
  rescue TimeoutError
    @tn.binmode = binmode_tmp
    return result
  end
end


# main body if used as a executable
# Here are sample usages
if __FILE__ ==  $PROGRAM_NAME
  crawler = Crawler.new(:host => 'ptt.cc', :username => ARGV[0], :password => ARGV[1])
  crawler.login
  puts crawler.search_article_by_id('#1Hl8-Aly', 'gossiping')
end
