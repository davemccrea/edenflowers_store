defmodule EdenflowersWeb.PaymentLinkRedirectControllerTest do
  use EdenflowersWeb.ConnCase, async: false

  setup do
    previous = Application.get_env(:edenflowers, :maintenance_mode, false)
    on_exit(fn -> Application.put_env(:edenflowers, :maintenance_mode, previous) end)
  end

  for maintenance? <- [false, true],
      {old_path, new_path} <- [{"/pay/token", "/pay/orders/token"}, {"/courses/pay/token", "/pay/courses/token"}],
      query <- ["", "?redirect_status=succeeded&payment_intent=pi_old&payment_intent_client_secret=secret%2Bvalue"] do
    @tag maintenance?: maintenance?, old_path: old_path, new_path: new_path, query: query
    test "redirects #{old_path} with query=#{inspect(query)} (maintenance=#{maintenance?})", ctx do
      Application.put_env(:edenflowers, :maintenance_mode, ctx.maintenance?)

      assert ctx.conn |> get(ctx.old_path <> ctx.query) |> redirected_to() == ctx.new_path <> ctx.query
    end
  end
end
