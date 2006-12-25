#########################################################################
#  OpenKore - Task framework
#  Copyright (c) 2006 OpenKore Team
#
#  This software is open source, licensed under the GNU General Public
#  License, version 2.
#  Basically, this means that you're allowed to modify and distribute
#  this software. However, if you distribute modified versions, you MUST
#  also distribute the source code.
#  See http://www.gnu.org/licenses/gpl.html for the full license.
#########################################################################
##
# MODULE DESCRIPTION: Task manager.
#
# Please read
# <a href="http://www.openkore.com/wiki/index.php/AI_subsystem_and_task_framework_overview">
# the AI subsystem and task framework overview
# </a>
# for an overview.
package TaskManager;

use strict;
use Carp::Assert;
use Task;
use Utils::Set;
use Utils::CallbackList;

##
# TaskManager->new()
#
# Create a new TaskManager.
sub new {
	my ($class) = @_;
	my %self = (
		# Set<Task>
		# Indexed set of currently active tasks.
		# Invariant:
		#     for all $task in activeTasks:
		#         $task->getStatus() == Task::RUNNING or Task::STOPPED
		#         !$inactiveTasks->has($task)
		#         if $task is not in $grayTasks:
		#             $task owns all its mutexes.
		activeTasks => new Set(),

		# Set<Task>
		# Indexed set of currently inactive tasks.
		# Invariant:
		#     for all $task in inactiveTasks:
		#         $task->getStatus() == Task::INTERRUPTED or Task::INACTIVE
		#         !$activeTasks->has($task)
		#         $task owns none of its mutexes.
		inactiveTasks => new Set(),

		# Hash<String, Task>
		#
		# Currently active mutexes. The keys are the mutex names, and the
		# values are the tasks that have a lock on the mutex (the mutex owner).
		#
		# Invariant: all tasks in $activeMutexes appear in $activeTasks.
		activeMutexes => {},

		# Set<Task>
		# Indexed set of tasks for which the mutex list has changed. These tasks
		# must be re-scheduled.
		# Invariant:
		#     for all $task in grayTasks:
		#         $task->getStatus() == Task::RUNNING
		#         $activeTasks->has($task)
		#         !$inactiveTasks->has($task)
		grayTasks => new Set(),

		# Maps a Task to an onMutexChanged callback ID. Used to unregister callbacks.
		# Invariant: Every task in $activeTasks and $inactiveTasks is in $mutexesChangedEvents.
		mutexesChangedEvents => {},

		# Whether tasks should be rescheduled on the
		# next iteration.
		shouldReschedule => 0,

		onTaskDone => new CallbackList('onTaskDone')
	);
	return bless \%self, $class;
}

##
# void $TaskManager->add(Task task)
# Requires: $task->getStatus() == Task::INACTIVE
#
# Add a new task to this task manager.
sub add {
	my ($self, $task) = @_;
	assert(defined $task) if DEBUG;
	assert($task->getStatus() == Task::INACTIVE) if DEBUG;
	$self->{inactiveTasks}->add($task);
	$self->{shouldReschedule} = 1;

	my $ID = $task->onMutexesChanged->add($self, \&onMutexesChanged);
	$self->{mutexChangedEvents}{$task} = $ID;
}

# Reschedule tasks. Do not call this method directly!
sub reschedule {
	my ($self) = @_;
	my $activeTasks      = $self->{activeTasks};
	my $inactiveTasks    = $self->{inactiveTasks};
	my $grayTasks        = $self->{grayTasks};
	my $activeMutexes    = $self->{activeMutexes};
	my $oldActiveTasks   = $activeTasks->deepCopy();
	my $oldInactiveTasks = $inactiveTasks->deepCopy();

	# The algorithm produces the following result:
	# All active tasks do not conflict with each other, such tasks with higher
	# priority will be active compared to conflicting tasks with lower priority.
	#
	# This algorithm does not produce the optimal result as that would take
	# far too much time, but the result should be good enough in most cases.

	# Deactivate gray tasks that conflict with active mutexes.
	while (@{$grayTasks} > 0) {
		my $task = $grayTasks->get(0);
		my $hasConflict = 0;
		foreach my $mutex (@{$task->getMutexes()}) {
			if (exists $activeMutexes->{$mutex}) {
				$hasConflict = 1;
				last;
			}
		}

		if ($hasConflict) {
			# There is a conflict, so make this task inactive.
			deactivateTask($activeTasks, $inactiveTasks,
				$grayTasks, $activeMutexes, $task);
		} else {
			# No conflict, so assign mutex ownership to this task.
			foreach my $mutex (@{$task->getMutexes()}) {
				$activeMutexes->{$mutex} = $task;
			}
			shift @{$grayTasks};
		}
	}

	# Activate inactive tasks such that active tasks don't conflict with each other.
	for (my $i = 0; $i < @{$inactiveTasks}; $i++) {
		my $task = $inactiveTasks->get($i);
		# Check whether this task conflicts with the currently locked mutexes.
		my @conflictingMutexes = intersect($activeMutexes, $task->getMutexes());

		if (@conflictingMutexes == 0) {
			# No conflicts, we can activate this task.
			$activeTasks->add($task);
			$inactiveTasks->remove($task);
			$i--;
			foreach my $mutex (@{$task->getMutexes()}) {
				$activeMutexes->{$mutex} = $task;
			}

		} elsif (higherPriority($task, $activeMutexes, \@conflictingMutexes)) {
			# There are conflicts. Does this task have a higher priority
			# than all tasks specified by the conflicting mutexes?
			# If yes, let it steal the mutex, activate it and deactivate
			# the previous mutex owner.

			$activeTasks->add($task);
			$inactiveTasks->remove($task);
			$i--;

			foreach my $mutex (@{$task->getMutexes()}) {
				my $oldTask = $activeMutexes->{$mutex};
				if ($oldTask) {
					# Mutex was locked by lower priority task.
					# Deactivate old task.
					deactivateTask($activeTasks, $inactiveTasks,
						$grayTasks, $activeMutexes, $oldTask);
				}
				$activeMutexes->{$mutex} = $task;
			}
		}
	}

	# Resume/activate newly activated tasks.
	foreach my $task (@{$activeTasks}) {
		if (!$oldActiveTasks->has($task)) {
			if ($task->getStatus() == Task::INACTIVE) {
				$task->activate();
			} else {
				$task->resume();
			}
		}
	}

	# Interrupt newly deactivated tasks.
	foreach my $task (@{$inactiveTasks}) {
		if (!$oldInactiveTasks->has($task)) {
			$task->interrupt();
		}
	}

	$self->{shouldReschedule} = 0;
}

##
# void $TaskManager->checkValidity()
#
# Check whether the internal invariants are correct. Dies if that is not the case.
sub checkValidity {
	my ($self) = @_;
	my $activeTasks   = $self->{activeTasks};
	my $inactiveTasks = $self->{inactiveTasks};
	my $grayTasks     = $self->{grayTasks};
	my $activeMutexes = $self->{activeMutexes};

	foreach my $task (@{$activeTasks}) {
		die unless ($task->getStatus() == Task::RUNNING || $task->getStatus() == Task::STOPPED);
		die unless (!$inactiveTasks->has($task));
		if (!$grayTasks->has($task)) {
	 		foreach my $mutex (@{$task->getMutexes()}) {
	 			die unless ($activeMutexes->{$mutex} == $task);
 			}
 		}
	}
	foreach my $task (@{$inactiveTasks}) {
		my $status = $task->getStatus();
		die unless ($status = Task::INTERRUPTED || $status == Task::INACTIVE);
		die unless (!$activeTasks->has($task));
		foreach my $mutex (@{$task->getMutexes()}) {
			die unless ($activeMutexes->{$mutex} != $task);
		}
	}
	foreach my $task (@{$grayTasks}) {
		die unless ($activeTasks->has($task));
		die unless (!$inactiveTasks->has($task));
	}

	my $activeMutexes = $self->{activeMutexes};
	foreach my $mutex (keys %{$activeMutexes}) {
		my $owner = $activeMutexes->{$mutex};
		die unless $self->{activeTasks}->has($owner);
	}
}

##
# void $TaskManager->iterate()
#
# Reschedule tasks if necessary, and run one iteration of every active task.
sub iterate {
	my ($self) = @_;

	$self->checkValidity() if DEBUG;
	$self->reschedule() if ($self->{shouldReschedule});
	$self->checkValidity() if DEBUG;

	my $activeTasks = $self->{activeTasks};
	my $activeMutexes = $self->{activeMutexes};
	for (my $i = 0; $i < @{$activeTasks}; $i++) {
		my $task = $activeTasks->get($i);
		$task->iterate();

		# Remove tasks that are stopped or completed.
		my $status = $task->getStatus();
		if ($status == Task::DONE || $status == Task::STOPPED) {
			deactivateTask($activeTasks, $self->{inactiveTasks},
				$self->{grayTasks}, $activeMutexes, $task);
			my $ID = $self->{mutexChangedEvents}{$task};
			$task->onMutexesChanged->remove($ID);
			$i--;
			$self->{shouldReschedule} = 1;

			$self->{onTaskDone}->call($self, { task => $task });
		}
	}
	$self->checkValidity() if DEBUG;
}

##
# String $TaskManager->activeTasksString()
#
# Returns a string which describes the current active tasks.
sub activeTasksString {
	my ($self) = @_;
	return getTaskSetString($self->{activeTasks});
}

##
# String $TaskManager->activeTasksString()
#
# Returns a string which describes the current inactive tasks.
sub inactiveTasksString {
	my ($self) = @_;
	return getTaskSetString($self->{inactiveTasks});
}

sub getTaskSetString {
	my ($set) = @_;
	if (@{$set}) {
		my @names;
		foreach my $task (@{$set}) {
			push @names, $task->getName();
		}
		return join(', ', @names);
	} else {
		return '-';
	}
}

##
# CallbackList $TaskManager->onTaskDone()
#
# This event is triggered when a task is completed, either successfully
# or with an error.
#
# The event argument a hash containing this item:<br>
# <tt>task</tt> - The task that was completed.
sub onTaskDone {
	return $_[0]->{onTaskDone};
}

sub onMutexesChanged {
	my ($self, $task) = @_;
	if ($task->getStatus() == Task::RUNNING) {
		$self->{grayTasks}->add($task);
	}
	$self->{shouldReschedule} = 1;
}

# Return the intersection of the given sets.
#
# set1: A reference to a hash whose keys are the set elements.
# set2: A reference to an array which contains the elements in the set.
# Returns: An array containing the intersect elements.
sub intersect {
	my ($set1, $set2) = @_;
	my @result;
	foreach my $element (@{$set2}) {
		if (exists $set1->{$element}) {
			push @result, $element;
		}
	}
	return @result;
}

# Check whether $task has a higher priority than all tasks specified
# by the given mutexes.
#
# task: The task to check.
# mutexTaskMapper: A hash which maps a mutex name to a task that owns that mutex.
# mutexes: A list of mutexes to check.
# Requires: All elements in $mutexes can be successfully mapped by $mutexTaskMapper.
sub higherPriority {
	my ($task, $mutexTaskMapper, $mutexes) = @_;
	my $priority = $task->getPriority();
	my $result = 1;
	for (my $i = 0; $i < @{$mutexes} && $result; $i++) {
		my $task2 = $mutexTaskMapper->{$mutexes->[$i]};
		$result = $result && $priority > $task2->getPriority();
	}
	return $result;
}

# Deactivate an active task by removing it from the active task list
# and the gray list, and removing its mutex locks. If the task isn't
# completed or stopped, then it will be added to the inactive task list.
sub deactivateTask {
	my ($activeTasks, $inactiveTasks, $grayTasks, $activeMutexes, $task) = @_;

	my $status = $task->getStatus();
	if ($status != Task::DONE && $status != Task::STOPPED) {
		$inactiveTasks->add($task);
	}
	$activeTasks->remove($task);
	$grayTasks->remove($task);
	foreach my $mutex (@{$task->getMutexes()}) {
		if ($activeMutexes->{$mutex} == $task) {
			delete $activeMutexes->{$mutex};
		}
	}
}

# sub printTaskSet {
# 	my ($set, $name) = @_;
# 	my @names;
# 	foreach my $task (@{$set}) {
# 		push @names, $task->getName();
# 	}
# 	print "$name = " . join(',', @names) . "\n";
# }
# 
# sub printActiveMutexes {
# 	my ($activeMutexes) = @_;
# 	print "Active mutexes:\n";
# 	foreach my $mutex (keys %{$activeMutexes}) {
# 		print "$mutex -> owner = " . $activeMutexes->{$mutex}->getName . "\n";
# 	}
# }

1;
