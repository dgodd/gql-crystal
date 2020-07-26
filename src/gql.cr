require "json"

module GQL
  VERSION = "0.1.0"

  annotation Field
  end

  module Serializable
    annotation Options
    end

    macro included
      # Define a `new` directly in the included type,
      # so it overloads well with other possible initializes

      def self.new(pull : ::JSON::PullParser)
        new_from_json_pull_parser(pull)
      end

      private def self.new_from_json_pull_parser(pull : ::JSON::PullParser)
        instance = allocate
        instance.initialize(__pull_for_json_serializable: pull)
        GC.add_finalizer(instance) if instance.responds_to?(:finalize)
        instance
      end

      # When the type is inherited, carry over the `new`
      # so it can compete with other possible intializes

      macro inherited
        def self.new(pull : ::JSON::PullParser)
          new_from_json_pull_parser(pull)
        end
      end

      def self.graphql
        instance = allocate
        instance.graphql
      end

      {% options = @type.annotation(::GQL::Serializable::Options) %}
      {% if options %}
      {% root = @type %}
      class Outer
        include GQL::Serializable
        property data : ::{{root}}?
        property errors : JSON::Any::Type
      end

        {% if options && options[:query_args] %}
        {% query_args = "" %}
        {% method_args = "" %}
        {% tuple = "{ " %}
        {% for name, value in options[:query_args] %}
          {% query_args += "$#{name}: #{value}, " %}
          {% method_args += ", " if method_args.size > 0 %}
          {% method_args += "#{name.underscore} = nil" %}
          {% tuple += ", " if tuple.size > 2 %}
          {% tuple += "#{name}: #{name.underscore}" %}
        {% end %}
        {% tuple += " }" %}
        def self.post(client, variables : Hash | NamedTuple)
          reqBody = {
            "query" => "query(#{{{query_args}}}) #{::{{root}}.graphql}",
            "variables" => variables,
          }.to_json
          res = client.post(
            "/graphql",
            headers: HTTP::Headers{
              "Content-Type" => "application/json",
            },
            body: reqBody,
          )
          if res.status_code != 200
            raise "Expected Status OK: got #{res.status}"
          end
          data = ::{{root}}::Outer.from_json(res.body)
          if data.errors
            raise "GQL ERRORS: #{data.errors.inspect}"
          end
          data.data
        end

        def self.post(client, {{method_args.id}})
          post(client, {{tuple.id}})
        end
        {% end %}
      {% end %}
    end

    def initialize(*, __pull_for_json_serializable pull : ::JSON::PullParser)
      {% begin %}
        {% properties = {} of Nil => Nil %}
        {% for ivar in @type.instance_vars %}
          {% ann = ivar.annotation(::GQL::Field) %}
          {% unless ann && ann[:ignore] %}
            {%
              properties[ivar.id] = {
                type:        ivar.type,
                key:         ((ann && ann[:key] && ann[:key].id) || ivar.id.camelcase(lower: true)).stringify,
                has_default: ivar.has_default_value?,
                default:     ivar.default_value,
                nilable:     ivar.type.nilable?,
                root:        ann && ann[:root],
                converter:   ann && ann[:converter],
                presence:    ann && ann[:presence],
              }
            %}
          {% end %}
        {% end %}

        {% for name, value in properties %}
          %var{name} = nil
          %found{name} = false
        {% end %}

        %location = pull.location
        begin
          pull.read_begin_object
        rescue exc : ::JSON::ParseException
          raise ::JSON::MappingError.new(exc.message, self.class.to_s, nil, *%location, exc)
        end
        until pull.kind.end_object?
          %key_location = pull.location
          key = pull.read_object_key
          case key
          {% for name, value in properties %}
            when {{value[:key]}}
              %found{name} = true
              begin
                %var{name} =
                  {% if value[:nilable] || value[:has_default] %} pull.read_null_or { {% end %}

                  {% if value[:root] %}
                    pull.on_key!({{value[:root]}}) do
                  {% end %}

                  {% if value[:converter] %}
                    {{value[:converter]}}.from_json(pull)
                  {% else %}
                    ::Union({{value[:type]}}).new(pull)
                  {% end %}

                  {% if value[:root] %}
                    end
                  {% end %}

                {% if value[:nilable] || value[:has_default] %} } {% end %}
              rescue exc : ::JSON::ParseException
                raise ::JSON::MappingError.new(exc.message, self.class.to_s, {{value[:key]}}, *%key_location, exc)
              end
          {% end %}
          else
            raise ::JSON::MappingError.new("Unknown key", self.class.to_s, key, *%location, nil)
          end
        end
        pull.read_next

        {% for name, value in properties %}
          {% unless value[:nilable] || value[:has_default] %}
            if %var{name}.nil? && !%found{name} && !::Union({{value[:type]}}).nilable?
              raise ::JSON::MappingError.new("Missing JSON attribute: {{value[:key].id}}", self.class.to_s, nil, *%location, nil)
            end
          {% end %}

          {% if value[:nilable] %}
            {% if value[:has_default] != nil %}
              @{{name}} = %found{name} ? %var{name} : {{value[:default]}}
            {% else %}
              @{{name}} = %var{name}
            {% end %}
          {% elsif value[:has_default] %}
            @{{name}} = %var{name}.nil? ? {{value[:default]}} : %var{name}
          {% else %}
            @{{name}} = (%var{name}).as({{value[:type]}})
          {% end %}

          {% if value[:presence] %}
            @{{name}}_present = %found{name}
          {% end %}
        {% end %}
      {% end %}
    end

    protected def graphql
      out = "{\n"
      {% begin %}
        {% properties = {} of Nil => Nil %}
        {% for ivar in @type.instance_vars %}
          {% ann = ivar.annotation(::GQL::Field) %}
          {% unless ann && ann[:ignore] %}
            {% if ann && ann[:graphql] %}
              out += "  #{{{ann[:graphql]}}}"
            {% else %}
              out += "  #{{{ivar.id.camelcase(lower: true).stringify}}}"
            {% end %}
            {% if ann && ann[:sub] %}
              {% type = (ann && ann[:type]) || ivar.type %}
              out += " " + {{type}}.graphql.gsub(/^/m, "  ").strip
            {% end %}
            out += "\n"
          {% end %}
        {% end %}
      {% end %}
      out + "}"
    end

    macro use_json_discriminator(field, mapping)
      {% unless mapping.is_a?(HashLiteral) || mapping.is_a?(NamedTupleLiteral) %}
        {% mapping.raise "mapping argument must be a HashLiteral or a NamedTupleLiteral, not #{mapping.class_name.id}" %}
      {% end %}

      def self.new(pull : ::JSON::PullParser)
        location = pull.location

        discriminator_value = nil

        # Try to find the discriminator while also getting the raw
        # string value of the parsed JSON, so then we can pass it
        # to the final type.
        json = String.build do |io|
          JSON.build(io) do |builder|
            builder.start_object
            pull.read_object do |key|
              if key == {{field.id.stringify}}
                discriminator_value = pull.read_string
                builder.field(key, discriminator_value)
              else
                builder.field(key) { pull.read_raw(builder) }
              end
            end
            builder.end_object
          end
        end

        unless discriminator_value
          raise ::JSON::MappingError.new("Missing JSON discriminator field '{{field.id}}'", to_s, nil, *location, nil)
        end

        case discriminator_value
        {% for key, value in mapping %}
          when {{key.id.stringify}}
            {{value.id}}.from_json(json)
        {% end %}
        else
          raise ::JSON::MappingError.new("Unknown '{{field.id}}' discriminator value: #{discriminator_value.inspect}", to_s, nil, *location, nil)
        end
      end
    end
  end
end
