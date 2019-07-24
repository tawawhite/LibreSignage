<?php
/** \file
* Get an asset thumbnail of a slide.
*
* @method{GET}
* @auth{By cookie or token}
* @groups{admin|editor|display}
* @ratelimit_yes
*
* @request_start{application/json}
* @request{string,id,The ID of the slide.,required}
* @request{string,name,The name of the asset.,required}
* @request_end
*
* @response_start{The requested asset.}
* @response_end
*
* @status_start
* @status{200,On success.}
* @status{400,If the request parameters are invalid.}
* @status{401,If the caller is not allowed to get asset thumbnails.}
* @status{404,If the asset doesn't exist.}
* @status{404,If the asset doesn't have a thumbnail.}
* @status{404,If the slide doesn't exist.}
* @status_end
*/

namespace libresignage\api\endpoint\slide\asset;

require_once($_SERVER['DOCUMENT_ROOT'].'/../common/php/Config.php');

use libresignage\api\APIEndpoint;
use libresignage\api\APIException;
use libresignage\api\HTTPStatus;
use libresignage\common\php\slide\Slide;
use libresignage\common\php\slide\exceptions\SlideNotFoundException;
use libresignage\common\php\exceptions\ArgException;
use Symfony\Component\HttpFoundation\BinaryFileResponse;

APIEndpoint::GET(
	[
		'APIAuthModule' => ['cookie_auth' => TRUE],
		'APIRateLimitModule' => [],
		'APIQueryValidatorModule' => [
			'schema' => [
				'type' => 'object',
				'properties' => [
					'id' => ['type' => 'string'],
					'name' => ['type' => 'string']
				],
				'required' => ['id', 'name']
			]
		]
	],
	function($req, $module_data) {
		$slide = NULL;
		$asset = NULL;

		$params = $module_data['APIQueryValidatorModule'];
		$caller = $module_data['APIAuthModule']['user'];

		if (!$caller->is_in_group(['admin', 'editor', 'display'])) {
			throw new APIException(
				'User not authorized to view thumbnails.',
				HTTPStatus::UNAUTHORIZED
			);
		}

		$slide = new Slide();
		try {
			$slide->load($params->id);
		} catch (SlideNotFoundException $e) {
			throw new APIException(
				"Slide '{$params->id}' doesn't exist.",
				HTTPStatus::NOT_FOUND,
				$e
			);
		}

		try {
			$asset = $slide->get_uploaded_asset($params->name);
		} catch (ArgException $e) {
			throw new APIException(
				"Asset '{$params->name}' doesn't exist.",
				HTTPStatus::NOT_FOUND
			);
		}

		if ($asset->has_thumb()) {
			return new BinaryFileResponse($asset->get_internal_thumb_path());
		} else {
			throw new APIException(
				"Asset doesn't have a thumbnail.",
				HTTPStatus::NOT_FOUND
			);
		}
	}
);
