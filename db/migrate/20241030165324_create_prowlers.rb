class CreateProwlers < ActiveRecord::Migration[7.2]
  def change
    create_table :prowlers do |t|
      t.timestamps
    end
  end
end
