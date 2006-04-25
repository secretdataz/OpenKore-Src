#include <stdio.h>
#include <readline/readline.h>
#include <readline/history.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/poll.h>
#include <string.h>
#include <assert.h>
#include "consoleui.h"


// Hack: work around some memory corruption issues in readline
// by setting this variable to NULL before a rl_redisplay().
// It is unclear now to solve this problem correctly.
extern char *rl_display_prompt;

static pthread_mutex_t singletonLock = PTHREAD_MUTEX_INITIALIZER;


/**
 * This class delegates callback functions back to the ConsoleUI instance.
 */
class ConsoleUICallbacks {
public:
	static void *threadMain(void *arg) {
		return ConsoleUI::getInstance()->threadMain(arg);
	}

	static void lineRead(char *line) {
		ConsoleUI::getInstance()->lineRead(line);
	}
};


ConsoleUI *ConsoleUI::instance = NULL;

ConsoleUI::ConsoleUI() {
	thread = 0;
	pthread_mutex_init(&inputLock, NULL);
	pthread_mutex_init(&outputLock, NULL);
	pthread_cond_init(&outputCond, NULL);
}

ConsoleUI::~ConsoleUI() {
	stop();
	while (!input.empty()) {
		free(input.front());
		input.pop();
	}
	while (!output.empty()) {
		free(output.front());
		output.pop();
	}
	pthread_mutex_destroy(&inputLock);
	pthread_mutex_destroy(&outputLock);
	pthread_cond_destroy(&outputCond);
}

void
ConsoleUI::lineRead(char *line) {
	pthread_mutex_lock(&inputLock);
	input.push(line);
	pthread_mutex_unlock(&inputLock);
	add_history(line);
	lineProcessed = true;
}

bool
ConsoleUI::canRead() {
	struct pollfd ufds;
	ufds.fd = STDIN_FILENO;
	ufds.events = POLLIN;
	return poll(&ufds, 1, 0) == 1;
}

void *
ConsoleUI::threadMain(void *arg) {
	rl_callback_handler_install("", ConsoleUICallbacks::lineRead);
	while (!quit) {
		while (canRead()) {
			lineProcessed = false;
			rl_callback_read_char();
			if (lineProcessed && rl_prompt != NULL && rl_prompt[0] != '\0') {
				// If a line has been processed, reset the prompt
				// so we don't see it again after an Enter.
				rl_set_prompt("");
				rl_display_prompt = NULL;
				rl_redisplay();
			}
		}

		pthread_mutex_lock(&outputLock);
		if (!output.empty()) {
			processOutput();
			pthread_cond_broadcast(&outputCond);
		}
		pthread_mutex_unlock(&outputLock);

		usleep(10000);
	}
	rl_callback_handler_remove();
	return NULL;
}

void
ConsoleUI::processOutput() {
	FILE *stream = (rl_outstream == NULL) ? stdout : rl_outstream;
	int point, mark;
	char *buffer = NULL;
	char *prompt = NULL;

	// Save readline's state.
	point = rl_point;
	mark = rl_mark;
	if (rl_line_buffer != NULL) {
		buffer = strdup(rl_line_buffer);
	}
	if (rl_prompt != NULL) {
		prompt = strdup(rl_prompt);
	}
	rl_replace_line("", 0);
	rl_point = rl_mark = 0;
	rl_set_prompt("");
	rl_display_prompt = NULL;
	rl_redisplay();

	// If there was already a prompt, then print it to
	// the screen and clear the prompt.
	if (prompt != NULL && prompt[0] != '\0') {
		fputs(prompt, stream);
		prompt[0] = '\0';
	}

	while (!output.empty()) {
		char *msg = output.front();
		size_t len;

		len = strlen(msg);
		if (output.size() == 1 && len > 0 && msg[len - 1] != '\n') {
			// This is the last message and it doesn't end with a newline.
			// Use this message as prompt.
			rl_set_prompt(msg);

			// Prevent prompt from being set to an empty string.
			if (prompt != NULL) {
				free(prompt);
				prompt = NULL;
			}
		} else {
			fputs(msg, stream);
		}

		free(msg);
		output.pop();
	}

	// Restore readline's state.
	if (prompt != NULL) {
		rl_set_prompt(prompt);
		free(prompt);
	}
	if (buffer != NULL) {
		rl_insert_text(buffer);
		free(buffer);
	}
	rl_point = point;
	rl_mark = mark;

	rl_display_prompt = NULL;
	rl_redisplay();
	fflush(stream);
}

ConsoleUI *
ConsoleUI::getInstance() {
	pthread_mutex_lock(&singletonLock);
	if (instance == NULL) {
		instance = new ConsoleUI();
		atexit(cleanup);
	}
	pthread_mutex_unlock(&singletonLock);
	return instance;
}

void
ConsoleUI::start() {
	quit = false;
	rl_initialize();
	pthread_create(&thread, NULL, ConsoleUICallbacks::threadMain, NULL);
}

void
ConsoleUI::stop() {
	if (thread != 0) {
		quit = true;
		pthread_join(thread, NULL);
		thread = 0;
	}
}

void
ConsoleUI::print(const char *msg) {
	assert(msg != NULL);
	pthread_mutex_lock(&outputLock);
	output.push(strdup(msg));
	pthread_cond_broadcast(&outputCond);
	pthread_mutex_unlock(&outputLock);
}

void
ConsoleUI::waitUntilPrinted() {
	pthread_mutex_lock(&outputLock);
	while (!output.empty()) {
		pthread_cond_wait(&outputCond, &outputLock);
	}
	pthread_mutex_unlock(&outputLock);
}

char *
ConsoleUI::getInput() {
	char *result = NULL;

	pthread_mutex_lock(&inputLock);
	if (!input.empty()) {
		result = input.front();
		input.pop();
	}
	pthread_mutex_unlock(&inputLock);
	return result;
}

void
ConsoleUI::cleanup() {
	if (instance != NULL) {
		delete instance;
		instance = NULL;
	}
}
