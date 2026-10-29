defmodule Edenflowers.Payments.PaymentRetentionTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Repo

  for parent <- [:order, :course_registration] do
    @parent parent
    test "#{parent} with payment history cannot be deleted directly" do
      parent = @parent
      {record, table, parent_key} = create_parent(parent)
      original = generate(payment([{parent_key, record.id}, method: :cash]))

      assert_delete_restricted(table, record.id, "payments_#{parent_key}_fkey")
      assert Ash.get!(record.__struct__, record.id, authorize?: false).id == record.id

      assert [%{id: id}] = Ash.load!(record, :payments, authorize?: false).payments
      assert id == original.id
    end
  end

  test "a retained pending registration protects its course, but an unused course can be deleted" do
    registration = generate(course_registration())
    assert_delete_restricted("courses", registration.course_id, "course_registrations_course_id_fkey")
    assert Ash.get!(Edenflowers.Courses.Course, registration.course_id, authorize?: false)
    assert Ash.get!(Edenflowers.Courses.CourseRegistration, registration.id, authorize?: false)

    unused = generate(course())
    assert %{num_rows: 1} = Repo.query!("DELETE FROM courses WHERE id = $1", [Ecto.UUID.dump!(unused.id)])

    assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
             Ash.get(Edenflowers.Courses.Course, unused.id, authorize?: false)
  end

  defp create_parent(:order), do: {generate(order(state: :placed)), "orders", :order_id}

  defp create_parent(:course_registration),
    do: {generate(course_registration()), "course_registrations", :course_registration_id}

  defp assert_delete_restricted(table, id, constraint) do
    assert {:error, %Postgrex.Error{postgres: postgres}} =
             Repo.query("DELETE FROM #{table} WHERE id = $1", [Ecto.UUID.dump!(id)], mode: :savepoint)

    assert postgres.code == :foreign_key_violation
    assert postgres.constraint == constraint
  end
end
