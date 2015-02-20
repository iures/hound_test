class Socialstar
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Enum

  devise :omniauthable, :omniauth_providers => [:facebook, :instagram, :twitter, :google_oauth2]

  has_one :invitation_code

  CROWDTAP_ATTRIBUTES = [
    :country_code,
    :date_of_birth,
    :email,
    :fb_user_id,
    :first_name,
    :gender,
    :last_name,
    :social_media_access_tokens,
    :terms_of_service,
    :ethnicity,
    :relationship_status,
    :parenting_status,
    :zip_code
  ]

  VALID_SOCIAL_CHANNELS = {
    :blog      => [:name, :url, :visitors, :payment, :categories => []],
    :facebook  => [:username, :followers, :payment],
    :instagram => [:username, :followers, :payment],
    :pinterest => [:username, :followers, :payment],
    :tumblr    => [:username, :followers, :payment],
    :twitter   => [:username, :followers, :payment],
    :vine      => [:username, :followers, :payment],
    :youtube   => [:channel, :subscribers, :payment]
  }

  VALID_SOCIAL_CHANNELS.each do |network, fields|
    fields.each do |field|
      next if field == :payment
      if field.is_a? Hash
        field = field.keys.first
      end
      getter = "#{network}_#{field}".to_sym
      CROWDTAP_ATTRIBUTES.push getter

      define_method getter do
        if social_channels[network]
          social_channels[network][field]
        end
      end
    end
  end

  US_STATES = ['AL','AK','AZ','AR','CA','CO','CT','DE','FL','GA','HI','ID','IL','IN','IA','KS','KY',
               'LA','ME','MD','MA','MI','MN','MS','MO','MT','NE','NV','NH','NJ','NM','NY','NC','ND',
               'OH','OK','OR','PA','RI','SC','SD','TN','TX','UT','VT','VA','WA','WV','WI','WY','DC']
  CA_STATES = ['AB','BC','MB','NB','NL','NT','NS','NU','ON','PE','QC','SK','YT']
  VALID_STATES = US_STATES + CA_STATES

  BLOG_CATEGORIES = [
    "Lifestyle",
    "Parenting",
    "Beauty",
    "Fashion",
    "Foodie",
    "Tech",
    "Health/Fitness",
    "Home/Design",
    "Craft/DIY",
    "Finance/Business",
    "Music/Entertainment",
    "Cars/Auto",
    "Travel",
    "Pets",
    "Bridal/Event",
    "Vlogging",
    "Other"
  ]

  GENDERS = ['Male', 'Female']
  PAYMENT_METHODS = ['ZipMark', 'PayPal']

  field :country_code, :default => 'US'
  field :date_of_birth, :type => DateTime
  field :email, :default => ''
  field :encrypted_password, :default => ''
  field :fb_user_id
  field :first_name
  field :has_seen_tutorial, :type => Boolean, :default => false
  field :gender
  field :last_name
  field :mixpanel_member_id
  field :password
  field :password_confirmation
  field :provider
  field :referral_url
  field :social_media_access_tokens, :type => Hash, :default => {}
  field :crowdtap_member_id, :type => BSON::ObjectId
  field :terms_of_service, :type => Boolean, :default => true
  field :ethnicity
  field :parenting_status
  field :relationship_status
  field :address_state
  field :zip_code
  field :social_channels, :type => Hash, :default => {}
  field :admin, :type => Boolean, :default => false
  field :socialstar_verified, :type => Boolean, :default => false
  field :payment_method, :default => 'ZipMark'
  field :notes
  field :blog_name,           :type => String
  field :blog_url,            :type => String
  field :blog_visitors,       :type => Integer
  field :blog_payment,        :type => String
  field :blog_categories,     :type => Array,  :default => []
  field :facebook_username,   :type => String
  field :facebook_followers,  :type => Integer
  field :facebook_payment,    :type => String
  field :instagram_username,  :type => String
  field :instagram_followers, :type => Integer
  field :instagram_payment,   :type => String
  field :pinterest_username,  :type => String
  field :pinterest_followers, :type => Integer
  field :pinterest_payment,   :type => String
  field :twitter_username,    :type => String
  field :twitter_followers,   :type => Integer
  field :twitter_payment,     :type => String
  field :vine_username,       :type => String
  field :vine_followers,      :type => Integer
  field :vine_payment,        :type => String
  field :youtube_channel,     :type => String
  field :youtube_subscribers, :type => Integer
  field :youtube_payment,     :type => String

  enum :status, [:pending, :approved, :rejected, :accepted]

  validates :email,    format: { with: /\A([\w\.%\+\-]+)@([\w\-]+\.)+([\w]{2,})\z/i,
                                 message: "not a valid email" },
                                 allow_nil: true
  validates :zip_code, format: { with: /\A\d{5}$|^[A-Z|a-z]\d[A-Z|a-z] ?\d[A-Z|a-z]\d\z/i,
                                 message: "not a valid zipcode" },
                                 allow_nil: true
  validates :parenting_status, inclusion: { in: Crowdtap.info_poll_responses["parenting_status"],
                                            message: "Parenting status must be one of #{Crowdtap.info_poll_responses["parenting_status"].values.join(' ')}" },
                                            allow_nil: true
  validates :relationship_status, inclusion: { in: Crowdtap.info_poll_responses["relationship_status"],
                                            message: "Relationship status must be one of #{Crowdtap.info_poll_responses["relationship_status"].values.join(' ')}" },
                                            allow_nil: true
  validates :address_state,    inclusion: { in: Socialstar::VALID_STATES,
                                            message: "State must be one of #{Socialstar::VALID_STATES.join(' ')}" },
                                            allow_nil: true
  validates :gender,           inclusion: { in: Socialstar::GENDERS,
                                            message: "Gender must be one of #{Socialstar::GENDERS.join(' ')}" },
                                            allow_nil: true
  validates :payment_method,   inclusion: { in: Socialstar::PAYMENT_METHODS,
                                            message: "Payment method must be one of #{Socialstar::PAYMENT_METHODS.join(' ')}" },
                                            allow_nil: true
  validates :fb_user_id, :uniqueness => { :message => "Facebook account is already registered", :allow_nil => true }

  validate :valid_blog_categories
  validate :parse_date_of_birth
  validate :older_than_13_years

  before_validation :upcase_address_state
  before_save :set_country_code
  before_create :convert_follower_counts
  after_create :assign_invitation_code
  after_update :track_status_change, :if => :status_changed?

  def set_country_code
    if CA_STATES.include?(address_state)
      self.country_code = "CA"
    else
      self.country_code = "US"
    end
  end

  def update_attributes_from_auth_hash!(auth_hash)
    self.fb_user_id                             = auth_hash.uid
    self.provider                               = auth_hash.provider
    self.social_media_access_tokens['facebook'] = auth_hash.credentials.to_hash.symbolize_keys
    self.password                               = Devise.friendly_token[0, 20]
    self.status                                 = :accepted
    save!
  end

  def assign_invitation_code!(code)
    self.invitation_code = InvitationCode.where(:code => code).first
    self.save!
  end

  def attributes_for_crowdtap
    attributes = { :application_id => id }
    CROWDTAP_ATTRIBUTES.each do |attribute|
      attributes[attribute] = send(attribute)
    end
    attributes
  end

  def age
    (Time.now.to_date - self.date_of_birth).to_i/365 if self.date_of_birth
  end

  def visit
    tracker.set!
  end

  private

  def older_than_13_years
    if date_of_birth && date_of_birth > 13.years.ago.to_date
      errors.add(:date_of_birth, 'You must be 13 years or older to sign up')
    end
  end

  def parse_date_of_birth
    begin
      dob = attributes_before_type_cast["date_of_birth"]
      self.date_of_birth = DateTime.strptime("#{dob}", "%m/%d/%Y") if dob && dob.is_a?(String)
    rescue ArgumentError => e
      if e.message =~ /invalid date/
        errors.add(:date_of_birth, "Not a valid date")
      end
    end
  end

  def valid_blog_categories
    blog = social_channels["blog"]
    if blog && blog["categories"]
      blog["categories"].any? do |category|
        unless Socialstar::BLOG_CATEGORIES.include?(category)
          errors.add(:social_channels, "Blog categories must be one of #{Socialstar::BLOG_CATEGORIES.join(' ')}")
        end
      end
    end
  end

  def convert_follower_counts
    social_channels.each do |channel, fields|
      ["visitors", "subscribers", "followers"].each do |field|
        fields[field].try(:gsub!, ",", "")
      end
    end
  end

  def upcase_address_state
    self.address_state.try(:upcase!)
  end

  def assign_invitation_code
    self.invitation_code = InvitationCode.create!
    self.save!
  end

  def track_status_change
    properties = tracker.socialstar_event_properties
    properties.delete("mp_name_tag")
    tracker.track("Member Application #{ status.to_s.capitalize }", properties)
  end

  def tracker
    @tracker ||= SocialstarsMetricTracker.new({ :socialstar => self })
  end
end
