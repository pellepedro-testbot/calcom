import { z } from "zod";

export const ZCheckAvailabilityInputSchema = z.object({
  eventTypeId: z.number().int().positive(),
  startTime: z.string().datetime(),
  endTime: z.string().datetime(),
  timeZone: z.string().default("UTC"),
});

export type TCheckAvailabilityInputSchema = z.infer<
  typeof ZCheckAvailabilityInputSchema
>;

export const ZCreateBookingInputSchema = z.object({
  eventTypeId: z.number().int().positive(),
  startTime: z.string().datetime(),
  endTime: z.string().datetime(),
  timeZone: z.string().default("UTC"),
  name: z.string().min(1),
  email: z.string().email(),
  title: z.string().optional(),
  notes: z.string().optional(),
  guests: z.array(z.string().email()).optional().default([]),
  responses: z.record(z.unknown()).optional().default({}),
  language: z.string().default("en"),
  metadata: z.record(z.unknown()).optional().default({}),
});

export type TCreateBookingInputSchema = z.infer<
  typeof ZCreateBookingInputSchema
>;

export const ZBookingNotifyInputSchema = z.object({
  bookingUid: z.string(),
  notifyAttendees: z.boolean().default(true),
  notifyOrganizer: z.boolean().default(true),
});

export type TBookingNotifyInputSchema = z.infer<
  typeof ZBookingNotifyInputSchema
>;
