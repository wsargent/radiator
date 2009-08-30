=begin rdoc

= Address handling class

=end
#
#--
# Copyright (c) 1998-2003 Minero Aoki <aamine@loveruby.net>
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
# Note: Originally licensed under LGPL v2+. Using MIT license for Rails
# with permission of Minero Aoki.
#++

require 'tmail/encode'
require 'tmail/parser'


module TMail

  class Address

    include TextUtils

    def Address.parse( str )
      Parser.parse :ADDRESS, special_quote_address(str)
    end
    
    # Takes a string which is an address and adds quotation marks to special
    # edge case methods that the parser just barfs on.
    #
    # Right now just handles two edge cases:
    #
    # Full stop as the last character of the display name:
    #   Mikel A. <mikel@me.com>
    # Returns:
    #   "Mikel A." <mikel@me.com>
    #
    # Unquoted @ symbol in the display name:
    #   mikel@me.com <mikel@me.com>
    # Returns:
    #   "mikel@me.com" <mikel@me.com>
    #
    # Any other address not matching these patterns just gets returned as is. 
    def Address.special_quote_address(str)
      case
      # This handles the missing "" in an older version of Apple Mail.app
      # around the display name when the display name contains a '@'
      # like 'mikel@me.com <mikel@me.com>'
      # Just quotes it to: '"mikel@me.com" <mikel@me.com>'
      when str =~ /\A([^"].+@.+[^"])\s(<.*?>)\Z/
        return "\"#{$1}\" #{$2}"
      # This handles cases where 'Mikel A. <mikel@me.com>' which is a trailing
      # full stop before the address section.  Just quotes it to
      # '"Mikel A. <mikel@me.com>"
      when str =~ /\A(.*?\.)\s(<.*?>)\Z/
        return "\"#{$1}\" #{$2}"
      else
        str
      end
    end

    def address_group?
      false
    end

    def initialize( local, domain )
      if domain
        domain.each do |s|
          raise SyntaxError, 'empty word in domain' if s.empty?
        end
      end
      
      # This is to catch an unquoted "@" symbol in the local part of the
      # address.  Handles addresses like <"@"@me.com> and makes sure they
      # stay like <"@"@me.com> (previously were becomming <@@me.com>)
      if local && (local.join == '@' || local.join =~ /\A[^"].*?@.*?[^"]\Z/)
        @local = "\"#{local.join}\""
      else
        @local = local
      end

      @domain = domain
      @name   = nil
      @routes = []
    end

    attr_reader :name

    def name=( str )
      @name = str
      @name = nil if str and str.empty?
    end

    alias phrase  name
    alias phrase= name=

    attr_reader :routes

    def inspect
      "#<#{self.class} #{address()}>"
    end

    def local
      return nil unless @local
      return '""' if @local.size == 1 and @local[0].empty?
      # Check to see if it is an array before trying to map it
      if @local.respond_to?(:map)
        @local.map {|i| quote_atom(i) }.join('.')
      else
        quote_atom(@local)
      end
    end

    def domain
      return nil unless @domain
      join_domain(@domain)
    end

    def spec
      s = self.local
      d = self.domain
      if s and d
        s + '@' + d
      else
        s
      end
    end

    alias address  spec

    def ==( other )
      other.respond_to? :spec and self.spec == other.spec
    end

    alias eql? ==

    def hash
      @local.hash ^ @domain.hash
    end

    def dup
      obj = self.class.new(@local.dup, @domain.dup)
      obj.name = @name.dup if @name
      obj.routes.replace @routes
      obj
    end

    include StrategyInterface

    def accept( strategy, dummy1 = nil, dummy2 = nil )
      unless @local
        strategy.meta '<>'   # empty return-path
        return
      end

      spec_p = (not @name and @routes.empty?)
      if @name
        strategy.phrase @name
        strategy.space
      end
      tmp = spec_p ? '' : '<'
      unless @routes.empty?
        tmp << @routes.map {|i| '@' + i }.join(',') << ':'
      end
      tmp << self.spec
      tmp << '>' unless spec_p
      strategy.meta tmp
      strategy.lwsp ''
    end

  end


  class AddressGroup

    include Enumerable

    def address_group?
      true
    end

    def initialize( name, addrs )
      @name = name
      @addresses = addrs
    end

    attr_reader :name
    
    def ==( other )
      other.respond_to? :to_a and @addresses == other.to_a
    end

    alias eql? ==

    def hash
      map {|i| i.hash }.hash
    end

    def []( idx )
      @addresses[idx]
    end

    def size
      @addresses.size
    end

    def empty?
      @addresses.empty?
    end

    def each( &block )
      @addresses.each(&block)
    end

    def to_a
      @addresses.dup
    end

    alias to_ary to_a

    def include?( a )
      @addresses.include? a
    end

    def flatten
      set = []
      @addresses.each do |a|
        if a.respond_to? :flatten
          set.concat a.flatten
        else
          set.push a
        end
      end
      set
    end

    def each_address( &block )
      flatten.each(&block)
    end

    def add( a )
      @addresses.push a
    end

    alias push add
    
    def delete( a )
      @addresses.delete a
    end

    include StrategyInterface

    def accept( strategy, dummy1 = nil, dummy2 = nil )
      strategy.phrase @name
      strategy.meta ':'
      strategy.space
      first = true
      each do |mbox|
        if first
          first = false
        else
          strategy.meta ','
        end
        strategy.space
        mbox.accept strategy
      end
      strategy.meta ';'
      strategy.lwsp ''
    end

  end

end   # module TMail
