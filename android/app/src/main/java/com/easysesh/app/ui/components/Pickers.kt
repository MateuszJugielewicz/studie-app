package com.easysesh.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.material3.AlertDialog
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.easysesh.app.core.Dates
import com.easysesh.app.ui.theme.Theme
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset

/** A date chip that opens the date picker (iOS compact DatePicker). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DateButton(date: LocalDate, min: LocalDate? = null, max: LocalDate? = null, onChange: (LocalDate) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val zone = ZoneId.systemDefault()
    Txt(
        Dates.abbreviated(date.atStartOfDay(zone).toInstant()),
        Modifier.background(Theme.fill, RoundedCornerShape(8.dp)).clickable { open = true }.padding(horizontal = 10.dp, vertical = 6.dp),
        style = Type.body,
    )
    if (open) {
        val state = rememberDatePickerState(
            initialSelectedDateMillis = date.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
            selectableDates = object : SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long): Boolean {
                    val d = Instant.ofEpochMilli(utcTimeMillis).atZone(ZoneOffset.UTC).toLocalDate()
                    return (min == null || !d.isBefore(min)) && (max == null || !d.isAfter(max))
                }
            },
        )
        DatePickerDialog(
            onDismissRequest = { open = false },
            confirmButton = {
                TextButton({
                    state.selectedDateMillis?.let { onChange(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()) }
                    open = false
                }) { T("OK", color = Theme.accent) }
            },
            dismissButton = { TextButton({ open = false }) { T("Cancel", color = Theme.secondary) } },
            colors = DatePickerDefaults.colors(containerColor = Theme.card),
        ) { DatePicker(state, colors = DatePickerDefaults.colors(containerColor = Theme.card, selectedDayContainerColor = Theme.accent, todayDateBorderColor = Theme.accent)) }
    }
}

/** A time chip that opens the time picker. Value in minutes after midnight. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TimeButton(minutes: Int, onChange: (Int) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val time = LocalTime.of((minutes / 60) % 24, minutes % 60)
    Txt(
        Dates.time(LocalDate.now().atTime(time).atZone(ZoneId.systemDefault()).toInstant()),
        Modifier.background(Theme.fill, RoundedCornerShape(8.dp)).clickable { open = true }.padding(horizontal = 10.dp, vertical = 6.dp),
        style = Type.body,
    )
    if (open) {
        val state = rememberTimePickerState(time.hour, time.minute, is24Hour = true)
        AlertDialog(
            onDismissRequest = { open = false },
            containerColor = Theme.card,
            confirmButton = { TextButton({ onChange(state.hour * 60 + state.minute); open = false }) { T("OK", color = Theme.accent) } },
            dismissButton = { TextButton({ open = false }) { T("Cancel", color = Theme.secondary) } },
            text = { TimePicker(state) },
        )
    }
}

@Composable
fun FormDateRow(title: String, date: LocalDate, min: LocalDate? = null, max: LocalDate? = null, onChange: (LocalDate) -> Unit) {
    FormRow {
        T(title, Modifier.weight(1f), style = Type.body)
        DateButton(date, min, max, onChange)
    }
}

@Composable
fun FormTimeRow(title: String, minutes: Int, onChange: (Int) -> Unit) {
    FormRow {
        T(title, Modifier.weight(1f), style = Type.body)
        TimeButton(minutes, onChange)
    }
}
