class CreateSkills < ActiveRecord::Migration[8.0]
  def change
    create_table :skills do |t|
      t.string :name
      t.text :description
      t.text :content

      t.timestamps
    end
  end
end
