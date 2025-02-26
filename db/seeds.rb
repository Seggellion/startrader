britannia_shard = Shard.find_or_create_by!(name: "Britannia", region: "Central")

City.all.each do |city|
    [
        { category: "wood", subcategory: "logs", item_name: "oak", base_price: 1.0, current_price: 1.0 },
        { category: "wood", subcategory: "logs", item_name: "spruce", base_price: 1.1, current_price: 1.1},
        { category: "wood", subcategory: "logs", item_name: "birch", base_price: 1.0, current_price: 1.0},
        { category: "wood", subcategory: "logs", item_name: "jungle", base_price: 1.2, current_price: 1.2},
        { category: "wood", subcategory: "logs", item_name: "acacia", base_price: 1.1, current_price: 1.1},
        { category: "wood", subcategory: "logs", item_name: "dark_oak", base_price: 1.3, current_price: 1.3},
        { category: "wood", subcategory: "logs", item_name: "mangrove", base_price: 1.2, current_price: 1.2},
        { category: "wood", subcategory: "logs", item_name: "cherry_blossom", base_price: 1.5, current_price: 1.5},
        { category: "food", subcategory: "fish", item_name: "cod", base_price: 0.4, current_price:0.4},
        { category: "food", subcategory: "fish", item_name: "salmon", base_price: 1.6, current_price:1.6},
        { category: "food", subcategory: "fish", item_name: "tuna", base_price: 1.5, current_price:1.5 },
        { category: "food", subcategory: "fish", item_name: "trout", base_price: 0.5, current_price: 0.5 },
        { category: "food", subcategory: "fish", item_name: "swordfish", base_price: 2.6, current_price: 2.6 },
        
        { category: "metal", subcategory: "ingots", item_name: "tin", base_price: 4, current_price: 4 },
        { category: "metal", subcategory: "ingots", item_name: "copper", base_price: 6, current_price: 6 },
        { category: "metal", subcategory: "ingots", item_name: "iron", base_price: 8, current_price: 8 },
        { category: "metal", subcategory: "ingots", item_name: "gold", base_price: 16, current_price: 16 },
        { category: "metal", subcategory: "ingots", item_name: "shadow iron", base_price: 12, current_price: 12 },
        { category: "metal", subcategory: "ingots", item_name: "agapite", base_price: 20, current_price: 20 },
        { category: "metal", subcategory: "ingots", item_name: "verite", base_price: 32, current_price: 32 },
        { category: "metal", subcategory: "ingots", item_name: "valorite", base_price: 48, current_price: 48 },

            # Stone Blocks
        { category: "stone", subcategory: "blocks", item_name: "cobblestone", base_price: 1, current_price: 1 },
        { category: "stone", subcategory: "blocks", item_name: "stone", base_price: 2, current_price: 2 },
        { category: "stone", subcategory: "blocks", item_name: "andesite", base_price: 1.5, current_price: 1.5 },
        { category: "stone", subcategory: "blocks", item_name: "diorite", base_price: 1.5, current_price: 1.5 },
        { category: "stone", subcategory: "blocks", item_name: "granite", base_price: 1.5, current_price: 1.5 },
        { category: "stone", subcategory: "blocks", item_name: "tuff", base_price: 2, current_price: 2 },
        { category: "stone", subcategory: "blocks", item_name: "basalt", base_price: 2.5, current_price: 2.5 },
        { category: "stone", subcategory: "blocks", item_name: "blackstone", base_price: 3, current_price: 3 },
        { category: "stone", subcategory: "blocks", item_name: "limestone", base_price: 4, current_price: 4 },  
        { category: "stone", subcategory: "blocks", item_name: "quartz", base_price: 6, current_price: 6 }  
    ].each do |commodity_data|
      city.city_commodities.create!(commodity_data.merge(shard_id: britannia_shard.id))
    end
  end