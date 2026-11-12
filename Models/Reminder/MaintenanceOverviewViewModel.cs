namespace CarCareTracker.Models
{
    /// <summary>
    /// A single row in the garage-wide maintenance overview.
    /// </summary>
    public class MaintenanceOverviewItem
    {
        public int ReminderId { get; set; }
        public int VehicleId { get; set; }
        public string VehicleName { get; set; } = string.Empty;
        public string VehicleIdentifier { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public string Notes { get; set; } = string.Empty;
        public ReminderMetric UserMetric { get; set; }
        public ReminderUrgency Urgency { get; set; }
        public bool IsRecurring { get; set; }
        public bool HasDate => UserMetric == ReminderMetric.Date || UserMetric == ReminderMetric.Both;
        public bool HasOdometer => UserMetric == ReminderMetric.Odometer || UserMetric == ReminderMetric.Both;
        public DateTime DueDate { get; set; }
        public int DueDays { get; set; }
        public int DueOdometer { get; set; }
        public int DueDistance { get; set; }
        public int CurrentOdometer { get; set; }
        public string DistanceUnit { get; set; } = string.Empty;
        /// <summary>
        /// Projected days until an odometer-based reminder is due, based on the vehicle's recent usage rate.
        /// Null when there is not enough history to estimate.
        /// </summary>
        public int? ProjectedDays { get; set; }
        /// <summary>
        /// Best estimate of days until due, considering both date and projected odometer. Used for sorting.
        /// </summary>
        public int EffectiveDays { get; set; }
        /// <summary>
        /// Estimated calendar date this reminder comes due (earliest of due date and projected odometer date).
        /// </summary>
        public DateTime? EstimatedDueDate { get; set; }
        /// <summary>
        /// True when EstimatedDueDate comes from the odometer projection rather than a fixed due date.
        /// </summary>
        public bool IsEstimateProjected { get; set; }
    }
    public class MaintenanceOverviewViewModel
    {
        public List<MaintenanceOverviewItem> Items { get; set; } = new List<MaintenanceOverviewItem>();
        public List<KeyValuePair<int, string>> Vehicles { get; set; } = new List<KeyValuePair<int, string>>();
    }
}
