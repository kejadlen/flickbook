require 'rexml/document'
require 'cgi'

#
# CobraVsMongoose translates between XML documents and Ruby hashes according to the 
# rules of the BadgerFish convention (see http://badgerfish.ning.com/).
# It can also convert directly between XML and JSON using the JSON library.
#
class CobraVsMongoose

  class ParseError < RuntimeError
  end
  
  class << self

    #
    # Returns a Hash corresponding to the data structure of the given XML,
    # which should be a REXML::Document or anything that responds to to_s
    # with a string of valid XML.
    #
    # E.g.
    #  xml = '<alice><bob>charlie</bob><bob>david</bob></alice>'
    #  CobraVsMongoose.xml_to_hash(xml)
    #  # => { "alice" => { "bob" => [{ "$" => "charlie" }, { "$" => "david" }] } }
    #
    def xml_to_hash(xml)
      if xml.respond_to?(:root_node)
        doc = xml
      else
        doc = REXML::Document.new(xml.to_s)
      end     
      return xml_node_to_hash(doc.root_node)
    end
  
    #
    # Returns an XML string corresponding to the data structure of the given Hash.
    #
    # E.g.
    #  hash = { "alice" => { "$" => "bob", "@charlie" => "david" } }
    #  CobraVsMongoose.hash_to_xml(hash)
    #  # => "<alice charlie='david'>bob</alice>"
    #
    # Note that, due to the fact that Ruby's hashes do not preserve ordering, the 
    # order of XML elements is undefined. For a predictable order, see the 
    # sort_keys class attribute.
    #
    def hash_to_xml(hash)
      return nested_data_to_xml(hash.keys.first, hash.values.first)
    end
    
    #
    # Returns a JSON string corresponding to the given XML, the constraints
    # for which are as for xml_to_hash.
    #
    def xml_to_json(xml)
      require 'json'
      return xml_to_hash(xml).to_json
    end
    
    #
    # Returns an XML string corresponding to the given JSON string.
    #
    def json_to_xml(json)
      require 'json'
      return hash_to_xml(JSON.parse(json))
    end
    
    #
    # The sort_keys class attribute is useful for testing, when a predictable order 
    # is required in the generated XML. By setting CobraVsMongoose.sort_keys to true,
    # hash-derived elements within a scope will be sorted by their element name, whilst
    # attributes on an element will be sorted according to their name.
    #
    attr_accessor :sort_keys
  
  private

    def xml_node_to_hash(node, parent_namespaces={}) #:nodoc
      this_node = {}
      namespaces = parent_namespaces.dup
      node.attributes.each do |name, value|
        case name
        when 'xmlns'
          (namespaces['@xmlns'] ||= {})['$'] = value
        when /^xmlns:(.*)/
          (namespaces['@xmlns'] ||= {})[$1] = value
        else
          this_node["@#{name}"] = value
        end
      end
      node.each_child do |child|
        case child.node_type
        when :element
          key, value = child.expanded_name, xml_node_to_hash(child, namespaces)
        when :text
          key, value = '$', unescape(child.to_s).strip
          next if value.empty?
        end
        current = this_node[key]
        case current
        when Array
          this_node[key] << value
        when nil
          this_node[key] = value
        else
          this_node[key] = [current.dup, value]
        end
      end
      return this_node.merge(namespaces)
    end
    
    def nested_data_to_xml(name, item, known_namespaces=[]) #:nodoc:
      case item
      when Hash
        attributes = {}
        children = {}
        namespaces = known_namespaces.dup
        opt_order(item).each do |key, value|
          value = item[key]
          case key
          when '@xmlns'
            value.each do |ns_name, ns_value|
              full_ns_name = 'xmlns' << ((ns_name == '$') ? '' : ':' << ns_name)
              unless known_namespaces.include?(full_ns_name)
                namespaces << full_ns_name 
                attributes[full_ns_name] = ns_value
              end
            end
          when /^@(.*)/
            attributes[$1] = value
          else
            children[key] = value
          end
        end
        return make_tag(name, attributes) do
          opt_order(children).map { |tag, value|
            case tag
            when '$'
              escape(value)
            else
              nested_data_to_xml(tag, value, namespaces)
            end
          }.join
        end
      when Array
        return item.map{ |subitem| nested_data_to_xml(name, subitem, known_namespaces) }.join
      else
        raise ParseError, "unparseable type: #{item.class}"
      end
    end
    
    def make_tag(name, attributes={}) #:nodoc:
      attr_string = ' ' << opt_order(attributes).map{ |k, v| "#{k}='#{escape(v)}'"  }.join(' ')
      attr_string = '' if attr_string == ' '
      body = yield
      if body && !body.empty?
        return "<#{name}#{attr_string}>" << body << "</#{name}>"
      else
        return "<#{name}#{attr_string} />"
      end
      return result
    end
    
    def escape(str) #:nodoc:
      return CGI.escapeHTML(str)
    end
    
    def unescape(str) #:nodoc:
      return CGI.unescapeHTML(str)
    end
    
    def opt_order(hash)
      return sort_keys ? hash.sort_by{ |kv| kv.first } : hash 
    end
    
  end
end
