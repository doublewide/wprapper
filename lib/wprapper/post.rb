require 'active_support/core_ext/object/blank'

module Wprapper
  class Post < Base
    property :categories
    property :content
    property :processed_content
    property :identifier
    property :image_url
    property :portrait_image_url
    property :published_at
    property :title
    property :title_position
    property :url
    property :status
    property :author_id
    property :custom_fields
    property :type

    class Mapper
      def initialize(wp_post_hash)
        @wp_post_hash = wp_post_hash
      end

      def to_h
        r = @wp_post_hash

        {
          categories:         fetch_categories,
          content:            r.fetch('post_content'),
          processed_content:  r.fetch('post_processed_content'),
          identifier:         r.fetch('post_id'),
          image_url:          fetch_image_url,
          portrait_image_url: fetch_custom_field('portrait_image', nil),
          published_at:       r.fetch('post_date_gmt').to_time,
          title:              r.fetch('post_title'),
          title_position:     fetch_custom_field('title_position', nil),
          url:                r.fetch('link'),
          status:             r.fetch('post_status'),
          type:               r.fetch('post_type'),
          author_id:          r.fetch('post_author'),
          custom_fields:      fetch_custom_fields
        }
      end

      def fetch_image_url
        post_thumbnail = @wp_post_hash.fetch('post_thumbnail', {})

        if post_thumbnail.is_a?(Hash)
          post_thumbnail.fetch('link', nil)
        else
          post_thumbnail.first
        end
      end

      def fetch_custom_fields
        @custom_fields ||= @wp_post_hash.fetch('custom_fields', [])
      end

      def terms
        @wp_post_hash.fetch('terms', [])
      end

      def fetch_custom_field(key, default)
        field = fetch_custom_fields.find do |f|
          f.fetch('key') == key
        end

        if field.present?
          field.fetch('value')
        else
          default
        end
      end

      def fetch_categories
        terms
          .select { |t| t['taxonomy'] == 'category' }
          .map { |c| Category.new_from_wp(c) }
      end

      def fetch_term(taxonomy, default)
        term = terms.find do |t|
          t.fetch('taxonomy') == taxonomy
        end

        if term.present?
          term.fetch('name')
        else
          default
        end
      end
    end

    ORDER_ASC  = 'asc'
    ORDER_DESC = 'desc'
    POST_DATE  = 'post_date_gmt'
    POST_ID    = 'post_id'

    class << self
      def new_from_wp(r)
        new(Mapper.new(r).to_h)
      end

      def all(batch_size = 25, &block)
        offset = 0

        loop do
          posts = get_published_posts(count: batch_size, offset: offset, order_by: POST_ID, order: ORDER_ASC)

          posts.each(&block)

          posts_size = posts.size

          break if posts_size < batch_size

          offset += posts_size
        end
      end

      def get_published_posts(count:, offset:, order_by:, order:)
        filters = {
          number:      count,
          offset:      offset,
          order:       order,
          orderby:     order_by,
          post_status: 'publish',
          post_type:   'post'
        }

        wordpress.posts(filters).map do |r|
          Post.new_from_wp(r)
        end
      end

      def latest(count, offset = 0)
        get_published_posts(count: count, offset: offset, order_by: POST_DATE, order: ORDER_DESC)
      end

      def find(post_id)
        wp_post = wordpress.post(post_id)

        Post.new_from_wp(wp_post)
      end

      def upload_feature_image(post_id, filename, image_bytes)
        media = wordpress_json_api.upload_media(filename, image_bytes)

        Post.set_featured_image(post_id, media['ID'])
      end

      def set_featured_image(post_id, media_id)
        Post.wordpress.update_post(post_id, post_thumbnail: media_id)
      end

      def touch(post_id)
        Post.wordpress.update_post(post_id, {})
      end
    end

    def published?
      status == 'publish'
    end

    def post?
      type == 'post'
    end

    def update_custom_fields(new_custom_fields)
      new_custom_fields = cleanup_hash_of_nil_values(new_custom_fields)
      custom_fields_to_update = merge_custom_fields(new_custom_fields)

      Post.wordpress.update_post(identifier, custom_fields: custom_fields_to_update)
    end

    def attributes
      to_h.except(:categories, :author_id)
    end

    def fetch_custom_field(key, default = nil)
      field = find_custom_field_by_key(key)

      return field['value'] if field.present?

      default
    end

    private

      def find_custom_field_by_key(key)
        custom_fields.find { |e| key == e['key'] }
      end

      def cleanup_hash_of_nil_values(hash)
        hash.select { |_, value| value.present? }
      end

      def merge_custom_fields(new_custom_fields)
        new_custom_fields.map do |key, value|
          field = find_custom_field_by_key(key) || {}

          field['key']   = key
          field['value'] = value

          field
        end
      end
  end
end
