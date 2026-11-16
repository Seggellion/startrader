require "test_helper"

class Admin::MenuItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_admin
    @menu = Menu.create!(name: "Regression links")
    @item = @menu.menu_items.create!(title: "Original link", url: "/original", item_type: :custom)
  end

  test "new renders a nested item form" do
    get new_admin_menu_menu_item_url(@menu)
    assert_response :success
    assert_select "form[action='#{admin_menu_menu_items_path(@menu)}']"
  end

  test "create persists a nested item" do
    assert_difference "@menu.menu_items.count", 1 do
      post admin_menu_menu_items_url(@menu), params: { menu_item: { title: "New link", url: "/new", item_type: "custom" } }
    end
    assert_redirected_to edit_admin_menu_path(@menu)
    assert_equal "/new", @menu.menu_items.find_by!(title: "New link").url
  end

  test "edit renders the item" do
    get edit_admin_menu_menu_item_url(@menu, @item)
    assert_response :success
    assert_select "input[name='menu_item[title]'][value='Original link']"
  end

  test "update persists the item" do
    patch admin_menu_menu_item_url(@menu, @item), params: { menu_item: { title: "Updated link" } }
    assert_redirected_to edit_admin_menu_path(@menu)
    assert_equal "Updated link", @item.reload.title
  end

  test "destroy removes the item" do
    assert_difference "MenuItem.count", -1 do
      delete admin_menu_menu_item_url(@menu, @item)
    end
    assert_redirected_to edit_admin_menu_path(@menu)
  end

  test "parent update persists a nested item and renders the tree" do
    parent = @menu.menu_items.create!(title: "Parent", url: "/parent")
    patch admin_menu_menu_item_update_parent_url(@menu, @item),
          params: { menu_item: { parent_id: parent.id } }, as: :json
    assert_response :success
    assert_equal true, JSON.parse(response.body)["success"]
    assert_equal parent.id, @item.reload.parent_id
    get edit_admin_menu_url(@menu)
    assert_response :success
    assert_select "li[data-id='#{parent.id}'] li[data-id='#{@item.id}']"
  end

  test "parent update rejects cycles" do
    patch admin_menu_menu_item_update_parent_url(@menu, @item),
          params: { menu_item: { parent_id: @item.id } }, as: :json
    assert_response :success
    assert_equal false, JSON.parse(response.body)["success"]
    assert_nil @item.reload.parent_id
  end

  test "parent update rejects a different menu" do
    other = Menu.create!(name: "Other menu").menu_items.create!(title: "Foreign", url: "/foreign")
    patch admin_menu_menu_item_update_parent_url(@menu, @item),
          params: { menu_item: { parent_id: other.id } }, as: :json
    assert_equal false, JSON.parse(response.body)["success"]
    assert_nil @item.reload.parent_id
  end

  test "nested routes do not edit an item from another menu" do
    other_menu = Menu.create!(name: "Other menu")
    patch admin_menu_menu_item_url(other_menu, @item), params: { menu_item: { title: "Wrong menu" } }
    assert_response :not_found
    assert_equal "Original link", @item.reload.title
  end
end
