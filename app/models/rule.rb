class DiscourseChat::Rule < DiscourseChat::PluginModel
  KEY_PREFIX = 'rule:'

  # Setup ActiveRecord::Store to use the JSON field to read/write these values
  store :value, accessors: [ :channel_id, :type, :group_id, :category_id, :tags, :filter ], coder: JSON

  after_initialize :init_filter

  def init_filter
    self.filter ||= 'watch'
    self.type ||= 'normal'
  end

  validates :filter, inclusion: { in: %w(watch follow mute),
                                  message: "%{value} is not a valid filter" }

  validates :type, inclusion: { in: %w(normal group_message group_mention),
                                message: "%{value} is not a valid filter" }

  validate :channel_valid?, :category_valid?, :group_valid?, :tags_valid?

  def channel_valid?
    # Validate channel
    if not (DiscourseChat::Channel.where(id: channel_id).exists?)
      errors.add(:channel_id, "#{channel_id} is not a valid channel id")
    end
  end

  def category_valid?
    if type != 'normal' && !category_id.nil?
      errors.add(:category_id, "cannot be specified for that type of rule")
    end

    return unless type == 'normal'

    # Validate category
    if not (category_id.nil? || Category.where(id: category_id).exists?)
      errors.add(:category_id, "#{category_id} is not a valid category id")
    end
  end

  def group_valid?
    if type == 'normal' && !group_id.nil?
      errors.add(:group_id, "cannot be specified for that type of rule")
    end

    return if type == 'normal'

    # Validate group
    if not Group.where(id: group_id).exists?
      errors.add(:group_id, "#{group_id} is not a valid group id")
    end
  end

  def tags_valid?
    # Validate tags
    return if tags.nil?
    tags.each do |tag|
      if not Tag.where(name: tag).exists?
        errors.add(:tags, "#{tag} is not a valid tag")
      end
    end
  end

  # We never want an empty array, set it to nil instead
  def tags=(array)
    if array.nil? || array.empty?
      super(nil)
    else
      super(array)
    end
  end

  # These are only allowed to be integers
  %w(channel_id category_id group_id).each do |name|
    define_method "#{name}=" do |val|
      if val.nil? || val.blank?
        super(nil)
      else
        super(val.to_i)
      end
    end

  end

  # Mock foreign key
  # Could return nil
  def channel
    DiscourseChat::Channel.find_by(id: channel_id)
  end
  def channel=(val)
    self.channel_id = val.id
  end

  scope :with_type, ->(type) { where("value::json->>'type'=?", type.to_s) }

  scope :with_channel, ->(channel) { with_channel_id(channel.id) }
  scope :with_channel_id, ->(channel_id) { where("value::json->>'channel_id'=?", channel_id.to_s) }

  scope :with_category_id, ->(category_id) { category_id.nil? ? where("(value::json->'category_id') IS NULL OR json_typeof(value::json->'category_id')='null'") : where("value::json->>'category_id'=?", category_id.to_s) }
  scope :with_group_ids, ->(group_id) { where("value::json->>'group_id' IN (?)", group_id.map(&:to_s)) }

  scope :order_by_precedence, -> { order("CASE
                                          WHEN value::json->>'type' = 'group_mention' THEN 1
                                          WHEN value::json->>'type' = 'group_message' THEN 2
                                          ELSE 3
                                         END",
                                        "CASE
                                          WHEN value::json->>'filter' = 'mute' THEN 1
                                          WHEN value::json->>'filter' = 'watch' THEN 2
                                          WHEN value::json->>'filter' = 'follow' THEN 3
                                         END") }

end
