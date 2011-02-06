class Artist < ActiveRecord::Base
    validates :name,    :presence => true
    validates :path,    :presence => true
end
