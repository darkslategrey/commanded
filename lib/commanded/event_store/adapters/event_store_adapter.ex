defmodule Commanded.EventStore.Adapters.EventStore do
  @moduledoc """
  [EventStore](https://github.com/commanded/eventstore) adapter for
  [Commanded](https://github.com/commanded/commanded).

  **Note**: There are multiple EventStore modules referenced in this adapter.

    * The external event persistence library by Ben Smith (`EventStore`)
    * The internal EventStore behaviour (`Commanded.EventStore`)
    * The internal EventStore adapter   (`Commanded.EventStore.Adapters.EventStore`)
  """

  @behaviour Commanded.EventStore

  alias Commanded.EventStore.{EventData, RecordedEvent, SnapshotData}

  @doc """
  NOTE 2018-10-24_1532
  What's   the   point   of  this   child   spec?   It
  returns   an  empty   list,  appended   to  children
  in   Commanded.Supervisor,  which   means  that   it
  is  effectively  ignored.   If  this  adapter  would
  have   been   included  idiomatically   (i.e.,   not
  called   explicitly   as   `EventStore.child_spec()`
  in  `Commanded.Supervisor`), the  `mod.child_spec/1`
  function would have been called automatically.

  Also,   every   single   entry   in   children   are
  OTP-compliant modules  except for this one  (and its
  corresponding EventStore behaviour).
    * Registration behaviour -> LocalRegistry -> Registry
    * PubSub behaviour -> LocalPubSub -> Registry instances
    * Task.Supervisor -> no comment
    * Commanded.Aggregates.Supervisor -> no comment
    * Subscriptions -> GenServer

  Refresher on `child_spec([])`:
  https://elixirforum.com/t/genserver-and-child-spec/7994/2
  \
   \
  UPDATE 2018-10-25_1635
  The name is misleading, because it resembles the child specification(s) required by supervisors, but in returns a list of child specs (plural!) to processes supporting the adapter in its efforts to communicate with the EventStore implementation itself.
  + commanded/commanded-extreme-adapter
  Used for Greg Young's EventStore. Its `application.ex` starts the main supervisor, that in turn starts two support workers. Right now I think that this is unnecessarybecause it bypasses the idiomatic ways OTP applications are started in Elixir. That is, just putting these workers into the 
  STOP
  think this through. there is no application.ex in a lib. look at the notes again and on github, but I think I'm on the right track
  """
  @impl Commanded.EventStore
  def child_spec, do: []

  @impl Commanded.EventStore
  def append_to_stream(stream_uuid, expected_version, events) do
    EventStore.append_to_stream(
      stream_uuid,
      expected_version,
      Enum.map(events, &to_event_data/1)
    )
  end

  @impl Commanded.EventStore
  def stream_forward(stream_uuid, start_version \\ 0, read_batch_size \\ 1_000)

  def stream_forward(stream_uuid, start_version, read_batch_size) do
    case EventStore.stream_forward(stream_uuid, start_version, read_batch_size) do
      {:error, error} -> {:error, error}
      stream -> Stream.map(stream, &from_recorded_event/1)
    end
  end

  @impl Commanded.EventStore
  def subscribe(stream_uuid)

  def subscribe(:all), do: subscribe("$all")

  def subscribe(stream_uuid) do
    EventStore.subscribe(stream_uuid, mapper: &from_recorded_event/1)
  end

  @impl Commanded.EventStore
  def subscribe_to(stream_uuid, subscription_name, subscriber, start_from \\ :origin)

  def subscribe_to(:all, subscription_name, subscriber, start_from) do
    EventStore.subscribe_to_all_streams(
      subscription_name,
      subscriber,
      start_from: start_from,
      mapper: &from_recorded_event/1
    )
  end

  def subscribe_to(stream_uuid, subscription_name, subscriber, start_from) do
    EventStore.subscribe_to_stream(
      stream_uuid,
      subscription_name,
      subscriber,
      start_from: start_from,
      mapper: &from_recorded_event/1
    )
  end

  @impl Commanded.EventStore
  def ack_event(subscription, %RecordedEvent{event_number: event_number}) do
    EventStore.ack(subscription, event_number)
  end

  @impl Commanded.EventStore
  def unsubscribe(subscription) do
    EventStore.Subscriptions.Subscription.unsubscribe(subscription)
  end

  @impl Commanded.EventStore
  def read_snapshot(source_uuid) do
    case EventStore.read_snapshot(source_uuid) do
      {:ok, snapshot_data} -> {:ok, from_snapshot_data(snapshot_data)}
      err -> err
    end
  end

  @impl Commanded.EventStore
  def record_snapshot(%SnapshotData{} = snapshot) do
    EventStore.record_snapshot(to_snapshot_data(snapshot))
  end

  @impl Commanded.EventStore
  def delete_snapshot(source_uuid) do
    EventStore.delete_snapshot(source_uuid)
  end

  defp to_event_data(%EventData{} = event_data) do
    struct(EventStore.EventData, Map.from_struct(event_data))
  end

  defp from_recorded_event(%EventStore.RecordedEvent{} = event) do
    %EventStore.RecordedEvent{
      event_id: event_id,
      event_number: event_number,
      stream_uuid: stream_uuid,
      stream_version: stream_version,
      correlation_id: correlation_id,
      causation_id: causation_id,
      event_type: event_type,
      data: data,
      metadata: metadata,
      created_at: created_at
    } = event

    %RecordedEvent{
      event_id: event_id,
      event_number: event_number,
      stream_id: stream_uuid,
      stream_version: stream_version,
      correlation_id: correlation_id,
      causation_id: causation_id,
      event_type: event_type,
      data: data,
      metadata: metadata,
      created_at: created_at
    }
  end

  defp to_snapshot_data(%SnapshotData{} = snapshot) do
    struct(EventStore.Snapshots.SnapshotData, Map.from_struct(snapshot))
  end

  defp from_snapshot_data(%EventStore.Snapshots.SnapshotData{} = snapshot_data) do
    struct(SnapshotData, Map.from_struct(snapshot_data))
  end
end
