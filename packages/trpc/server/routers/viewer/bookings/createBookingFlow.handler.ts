import type { PrismaClient } from "@calcom/prisma";
import { HttpError } from "@calcom/lib/http-error";

import type { TrpcSessionUser } from "../../../types";
import type {
  TCheckAvailabilityInputSchema,
  TCreateBookingInputSchema,
  TBookingNotifyInputSchema,
} from "./createBookingFlow.schema";

type BookingFlowCtx = {
  ctx: {
    user: NonNullable<TrpcSessionUser>;
    prisma: PrismaClient;
  };
};

export type AvailabilityCheckResult = {
  available: boolean;
  reason: string | null;
  nextAvailableSlot: string | null;
};

/**
 * Step 1 of the booking flow: check whether a slot is available
 * for the given event type before attempting to create a booking.
 */
export const checkAvailabilityHandler = async ({
  ctx,
  input,
}: BookingFlowCtx & { input: TCheckAvailabilityInputSchema }): Promise<AvailabilityCheckResult> => {
  const { eventTypeId, startTime, endTime, timeZone } = input;

  const eventType = await ctx.prisma.eventType.findFirst({
    where: { id: eventTypeId },
    select: {
      id: true,
      length: true,
      minimumBookingNotice: true,
      beforeEventBuffer: true,
      afterEventBuffer: true,
    },
  });

  if (!eventType) {
    throw new HttpError({ statusCode: 404, message: `Event type ${eventTypeId} not found` });
  }

  const start = new Date(startTime);
  const now = new Date();

  // Check minimum booking notice
  if (eventType.minimumBookingNotice) {
    const noticeCutoff = new Date(
      now.getTime() + eventType.minimumBookingNotice * 60 * 1000
    );
    if (start < noticeCutoff) {
      return {
        available: false,
        reason: `Booking requires at least ${eventType.minimumBookingNotice} minutes notice`,
        nextAvailableSlot: noticeCutoff.toISOString(),
      };
    }
  }

  // Check for conflicting bookings in this window
  const conflict = await ctx.prisma.booking.findFirst({
    where: {
      eventTypeId,
      status: { in: ["ACCEPTED", "PENDING"] },
      startTime: { lt: new Date(endTime) },
      endTime: { gt: start },
    },
    select: { endTime: true },
  });

  if (conflict) {
    return {
      available: false,
      reason: "Slot is already booked",
      nextAvailableSlot: conflict.endTime.toISOString(),
    };
  }

  return { available: true, reason: null, nextAvailableSlot: null };
};

export type CreatedBooking = {
  uid: string;
  title: string;
  startTime: string;
  endTime: string;
  attendeeName: string;
  attendeeEmail: string;
  status: string;
};

/**
 * Step 2 of the booking flow: create a confirmed booking and
 * enqueue notifications.
 */
export const createBookingHandler = async ({
  ctx,
  input,
}: BookingFlowCtx & { input: TCreateBookingInputSchema }): Promise<CreatedBooking> => {
  const {
    eventTypeId,
    startTime,
    endTime,
    name,
    email,
    title,
    notes,
    language,
    metadata,
  } = input;

  // Verify event type exists
  const eventType = await ctx.prisma.eventType.findFirst({
    where: { id: eventTypeId },
    select: { id: true, title: true, userId: true, teamId: true },
  });

  if (!eventType) {
    throw new HttpError({ statusCode: 404, message: `Event type ${eventTypeId} not found` });
  }

  const bookingTitle = title ?? `${name} <> ${eventType.title}`;

  const booking = await ctx.prisma.booking.create({
    data: {
      title: bookingTitle,
      startTime: new Date(startTime),
      endTime: new Date(endTime),
      eventTypeId,
      userId: ctx.user.id,
      status: "ACCEPTED",
      description: notes,
      metadata: metadata ?? {},
      attendees: {
        create: [
          {
            name,
            email,
            locale: language,
            timeZone: input.timeZone,
          },
        ],
      },
    },
    select: {
      uid: true,
      title: true,
      startTime: true,
      endTime: true,
      status: true,
      attendees: { select: { name: true, email: true }, take: 1 },
    },
  });

  return {
    uid: booking.uid,
    title: booking.title,
    startTime: booking.startTime.toISOString(),
    endTime: booking.endTime.toISOString(),
    attendeeName: booking.attendees[0]?.name ?? name,
    attendeeEmail: booking.attendees[0]?.email ?? email,
    status: booking.status,
  };
};
