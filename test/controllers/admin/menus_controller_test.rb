require "test_helper"

class Admin::MenusControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_admin
    @menu = Menu.create!(name: "Regression menu")
  end

  test "index lists menus" do
    get admin_menus_url
    assert_response :success
    assert_select "td", text: @menu.name
  end

  test "new renders a menu form" do
    get new_admin_menu_url
    assert_response :success
    assert_select "form[action='#{admin_menus_path}']"
  end

  test "create persists a menu" do
    assert_difference "Menu.count", 1 do
      post admin_menus_url, params: { menu: { name: "New regression menu" } }
    end
    assert_redirected_to edit_admin_menu_path(Menu.order(:id).last)
  end

  test "edit renders the selected menu" do
    get edit_admin_menu_url(@menu)
    assert_response :success
    assert_select "input[name='menu[name]'][value='Regression menu']"
  end

  test "update persists the name" do
    patch admin_menu_url(@menu), params: { menu: { name: "Updated menu" } }
    assert_redirected_to edit_admin_menu_path(@menu)
    assert_equal "Updated menu", @menu.reload.name
  end

  test "destroy removes the menu" do
    assert_difference "Menu.count", -1 do
      delete admin_menu_url(@menu)
    end
    assert_redirected_to admin_menus_path
  end
end
