defmodule Edenflowers.Delivery.DriverTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Delivery.Driver

  setup do
    %{admin: generate(admin_user())}
  end

  describe "create" do
    test "generates a unique, non-nil link token", %{admin: admin} do
      one = generate(driver())
      two = generate(driver())

      assert is_binary(one.link_token) and one.link_token != ""
      assert is_binary(two.link_token) and two.link_token != ""
      refute one.link_token == two.link_token

      assert {:ok, created} = Driver.create(%{name: "Asko"}, actor: admin)
      assert is_binary(created.link_token)
      assert created.active?
      assert created.locale == "en-GB"
    end
  end

  describe "by_token" do
    test "resolves an existing token and returns nil for an unknown one", %{admin: admin} do
      driver = generate(driver())

      assert {:ok, %Driver{id: id}} = Driver.get_by_token(driver.link_token, actor: admin)
      assert id == driver.id
      assert {:ok, nil} = Driver.get_by_token("does-not-exist", actor: admin)
    end
  end

  describe "regenerate_token" do
    test "replaces the token so the previously copied link stops resolving", %{admin: admin} do
      driver = generate(driver())
      old_token = driver.link_token

      assert {:ok, regenerated} = Driver.regenerate_token(driver, actor: admin)
      refute regenerated.link_token == old_token

      assert {:ok, nil} = Driver.get_by_token(old_token, actor: admin)
      assert {:ok, %Driver{}} = Driver.get_by_token(regenerated.link_token, actor: admin)
    end
  end

  describe "deactivate" do
    test "preserves the row but drops it from the active pool", %{admin: admin} do
      driver = generate(driver())

      assert {:ok, deactivated} = Driver.deactivate(driver, actor: admin)
      refute deactivated.active?

      active_ids = Driver.list_active!(actor: admin) |> Enum.map(& &1.id)
      refute driver.id in active_ids

      all_ids = Driver.list!(actor: admin) |> Enum.map(& &1.id)
      assert driver.id in all_ids
    end

    test "can be reactivated", %{admin: admin} do
      driver = generate(driver())
      {:ok, deactivated} = Driver.deactivate(driver, actor: admin)

      assert {:ok, reactivated} = Driver.activate(deactivated, actor: admin)
      assert reactivated.active?
    end
  end

  describe "policies" do
    test "non-admins cannot create drivers or see them in a list" do
      generate(driver())

      assert {:error, %Ash.Error.Forbidden{}} = Driver.create(%{name: "Sneaky"}, actor: nil)
      assert {:ok, []} = Driver.list(actor: nil)
    end

    test "by_token is public (no actor required)" do
      driver = generate(driver())
      assert {:ok, %Driver{}} = Driver.get_by_token(driver.link_token, actor: nil)
    end
  end
end
