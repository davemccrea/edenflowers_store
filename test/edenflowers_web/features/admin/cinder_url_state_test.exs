defmodule EdenflowersWeb.Admin.CinderUrlStateTest do
  use ExUnit.Case, async: true

  alias EdenflowersWeb.Admin.ExpensesLive
  alias EdenflowersWeb.Admin.OrdersLive

  describe "orders table URL state" do
    test "assigns Cinder url_state from handle_params" do
      params = %{"page" => "2", "sort" => "-ordered_at", "search" => "anna"}
      uri = "http://www.example.com/admin/orders?page=2&sort=-ordered_at&search=anna"

      assert {:noreply, socket} =
               OrdersLive.handle_params(params, uri, %Phoenix.LiveView.Socket{})

      assert socket.assigns.url_state == %{
               filters: params,
               current_page: 2,
               sort_by: [{"ordered_at", :desc}],
               uri: uri
             }
    end
  end

  describe "expenses table URL state" do
    test "assigns Cinder url_state from handle_params" do
      params = %{"page" => "3", "sort" => "date", "category" => "supplies"}
      uri = "http://www.example.com/admin/expenses?page=3&sort=date&category=supplies"

      assert {:noreply, socket} =
               ExpensesLive.handle_params(params, uri, %Phoenix.LiveView.Socket{})

      assert socket.assigns.url_state == %{
               filters: params,
               current_page: 3,
               sort_by: [{"date", :asc}],
               uri: uri
             }
    end
  end
end
