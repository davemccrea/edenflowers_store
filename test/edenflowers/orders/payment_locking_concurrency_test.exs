defmodule Edenflowers.Orders.PaymentLockingConcurrencyTest do
  use ExUnit.Case

  import Generator

  alias Ecto.Adapters.SQL.Sandbox
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order
  alias Edenflowers.Repo

  test "line item mutation waits for payment confirmation and then fails" do
    %{order: order, line_item: line_item} = fixtures = create_fixtures()
    on_exit(fn -> delete_fixtures(fixtures) end)
    test_pid = self()

    confirmation =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          {:ok, {confirmed_order, notifications}} =
            Repo.transaction(fn ->
              Repo.query!("SELECT id FROM orders WHERE id = $1 FOR UPDATE", [Ecto.UUID.dump!(order.id)])
              send(test_pid, :order_locked)

              receive do
                :confirm_payment ->
                  {:ok, confirmed_order, notifications} =
                    Orders.begin_payment_confirmation(order,
                      authorize?: false,
                      return_notifications?: true
                    )

                  {confirmed_order, notifications}
              end
            end)

          Ash.Notifier.notify(notifications)
          {:ok, confirmed_order}
        end)
      end)

    assert_receive :order_locked

    mutation =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          %{rows: [[backend_pid]]} = Repo.query!("SELECT pg_backend_pid()")
          send(test_pid, {:mutation_started, backend_pid})
          result = Orders.increment_line_item(order, line_item.id, authorize?: false)
          send(test_pid, {:mutation_finished, result})
          result
        end)
      end)

    assert_receive {:mutation_started, backend_pid}
    assert_waiting_for_lock(backend_pid)
    refute_receive {:mutation_finished, _result}

    send(confirmation.pid, :confirm_payment)

    assert {:ok, %{state: :confirming_payment}} = Task.await(confirmation)
    assert {:error, %Ash.Error.Invalid{}} = Task.await(mutation)
    assert_receive {:mutation_finished, {:error, %Ash.Error.Invalid{}}}

    Sandbox.unboxed_run(Repo, fn ->
      assert %{state: :confirming_payment} = Ash.get!(Order, order.id, authorize?: false)
      assert %{quantity: 1} = Ash.get!(Edenflowers.Orders.LineItem, line_item.id, authorize?: false)
    end)
  end

  defp create_fixtures do
    Sandbox.unboxed_run(Repo, fn ->
      tax_rate = generate(tax_rate())
      category = generate(product_category())
      product = generate(product(tax_rate_id: tax_rate.id, product_category_id: category.id))
      variant = generate(product_variant(product_id: product.id))
      order = generate(order(state: :payment, payment_intent_id: "pi_lock_test"))
      line_item = generate(line_item(order_id: order.id, product_variant_id: variant.id))

      %{
        tax_rate: tax_rate,
        category: category,
        product: product,
        variant: variant,
        order: order,
        line_item: line_item
      }
    end)
  end

  defp delete_fixtures(fixtures) do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.query!("DELETE FROM orders WHERE id = $1", [Ecto.UUID.dump!(fixtures.order.id)])
      Ash.destroy!(fixtures.variant, authorize?: false)
      Ash.destroy!(fixtures.product, authorize?: false)
      Ash.destroy!(fixtures.category, authorize?: false)
      # TaxRate is archival: Ash.destroy only sets archived_at, and the kept row
      # would collide with a later run's generated name.
      Repo.query!("DELETE FROM tax_rates WHERE id = $1", [Ecto.UUID.dump!(fixtures.tax_rate.id)])
    end)
  end

  defp assert_waiting_for_lock(backend_pid, attempts \\ 50)

  defp assert_waiting_for_lock(_backend_pid, 0), do: flunk("line item mutation did not wait for the Order lock")

  defp assert_waiting_for_lock(backend_pid, attempts) do
    waiting? =
      Sandbox.unboxed_run(Repo, fn ->
        %{rows: rows} =
          Repo.query!("SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1", [backend_pid])

        rows == [["Lock"]]
      end)

    if waiting? do
      :ok
    else
      Process.sleep(10)
      assert_waiting_for_lock(backend_pid, attempts - 1)
    end
  end
end
