module OvirtRefresherSpecCommon
  extend ActiveSupport::Concern

  def serialize_inventory(models = [])
    skip_attributes = %w(updated_on last_refresh_date updated_at last_updated finish_time)
    inventory = {}
    models.each do |model|
      inventory[model.name] = model.all.collect do |rec|
        rec.attributes.except(*skip_attributes)
      end
    end
    inventory
  end
end
